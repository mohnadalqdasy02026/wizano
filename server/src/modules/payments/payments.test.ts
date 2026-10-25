// اختبارات تكامل وحدة المدفوعات — على قاعدة wizano_test الحقيقية.
// تغطي: الدفعة العامة والمرتبطة بعملية، حساب الرصيد بعد الدفعة، رقم الدفعة الفريد،
// القيود (مبلغ موجب، منع تجاوز المتبقي/الرصيد)، منع التكرار (UUID/Idempotency-Key)،
// العزل بين المحلات، والقائمة والتفاصيل.

import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { and, eq, inArray } from "drizzle-orm";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { migrate } from "drizzle-orm/postgres-js/migrator";
import { buildApp } from "../../app.js";
import { createDb, type Database, type SqlClient } from "../../db/index.js";
import {
  customerShopLinks,
  customers,
  payments,
  purchases,
  refreshTokens,
  shopCounters,
  shopMembers,
  shops,
  syncOperations,
  users,
} from "../../db/schema.js";

const migrationsFolder = path.join(
  path.dirname(fileURLToPath(import.meta.url)),
  "../../db/migrations",
);

const OWNER_EMAIL = "pay-test+owner@example.com";
const OTHER_EMAIL = "pay-test+other@example.com";
const PASSWORD = "PayTest12345";

let app: Awaited<ReturnType<typeof buildApp>>;
let db: Database;
let client: SqlClient;

async function cleanup(): Promise<void> {
  const rows = await db
    .select({ id: users.id })
    .from(users)
    .where(inArray(users.email, [OWNER_EMAIL, OTHER_EMAIL]));
  const userIds = rows.map((r) => r.id);
  if (userIds.length === 0) return;

  const memberships = await db
    .select({ shopId: shopMembers.shopId })
    .from(shopMembers)
    .where(inArray(shopMembers.userId, userIds));
  const shopIds = [...new Set(memberships.map((m) => m.shopId))];

  if (shopIds.length > 0) {
    await db.delete(syncOperations).where(inArray(syncOperations.shopId, shopIds));
    await db.delete(payments).where(inArray(payments.shopId, shopIds));
    await db.delete(purchases).where(inArray(purchases.shopId, shopIds));
    const linkRows = await db
      .select({ customerId: customerShopLinks.customerId })
      .from(customerShopLinks)
      .where(inArray(customerShopLinks.shopId, shopIds));
    const customerIds = [...new Set(linkRows.map((l) => l.customerId))];
    await db
      .delete(customerShopLinks)
      .where(inArray(customerShopLinks.shopId, shopIds));
    if (customerIds.length > 0) {
      await db.delete(customers).where(inArray(customers.id, customerIds));
    }
    await db.delete(shopCounters).where(inArray(shopCounters.shopId, shopIds));
    await db.delete(shopMembers).where(inArray(shopMembers.shopId, shopIds));
    await db.delete(shops).where(inArray(shops.id, shopIds));
  }
  await db.delete(refreshTokens).where(inArray(refreshTokens.userId, userIds));
  await db.delete(users).where(inArray(users.id, userIds));
}

async function registerAndLogin(email: string): Promise<string> {
  const reg = await app.inject({
    method: "POST",
    url: "/api/v1/auth/register",
    payload: { displayName: "مستخدم", email, password: PASSWORD },
  });
  if (reg.statusCode === 201) return reg.json().data.tokens.accessToken;
  const login = await app.inject({
    method: "POST",
    url: "/api/v1/auth/login",
    payload: { email, password: PASSWORD },
  });
  return login.json().data.tokens.accessToken;
}

async function createShop(token: string, name: string): Promise<string> {
  const res = await app.inject({
    method: "POST",
    url: "/api/v1/shops",
    headers: { authorization: `Bearer ${token}` },
    payload: { name },
  });
  return res.json().data.id;
}

async function createCustomer(
  token: string,
  shopId: string,
  name = "عميل",
): Promise<string> {
  const res = await app.inject({
    method: "POST",
    url: `/api/v1/shops/${shopId}/customers`,
    headers: { authorization: `Bearer ${token}` },
    payload: { displayName: name },
  });
  return res.json().data.id;
}

async function createPurchase(
  token: string,
  shopId: string,
  customerId: string,
  total: number,
  paid = 0,
): Promise<string> {
  const res = await app.inject({
    method: "POST",
    url: `/api/v1/shops/${shopId}/purchases`,
    headers: { authorization: `Bearer ${token}` },
    payload: { customerId, itemsText: "بضاعة", totalAmount: total, paidAmount: paid },
  });
  return res.json().data.id;
}

beforeAll(async () => {
  ({ db, client } = createDb());
  await migrate(db, { migrationsFolder });
  await cleanup();
  app = await buildApp({
    authDeps: { db },
    shopsDeps: { db },
    customersDeps: { db },
    purchasesDeps: { db },
    paymentsDeps: { db },
  });
}, 60000);

afterAll(async () => {
  if (db) await cleanup();
  if (app) await app.close();
  if (client) await client.end({ timeout: 5 });
});

describe("وحدة المدفوعات", () => {
  it("يرفض الوصول بدون رمز مصادقة", async () => {
    const token = await registerAndLogin(OWNER_EMAIL);
    const shopId = await createShop(token, "محل رفض الدفع");
    const res = await app.inject({
      method: "GET",
      url: `/api/v1/shops/${shopId}/payments`,
    });
    expect(res.statusCode).toBe(401);
  });

  it("يسجّل دفعة عامة ويحسب الرصيد بعدها", async () => {
    const token = await registerAndLogin(OWNER_EMAIL);
    const shopId = await createShop(token, "محل دفع عام");
    const customerId = await createCustomer(token, shopId, "سالم");
    await createPurchase(token, shopId, customerId, 10000, 0);

    const res = await app.inject({
      method: "POST",
      url: `/api/v1/shops/${shopId}/payments`,
      headers: { authorization: `Bearer ${token}` },
      payload: { customerId, amount: 4000 },
    });
    expect(res.statusCode).toBe(201);
    const data = res.json().data;
    expect(data.amount).toBe("4000");
    expect(data.purchaseId).toBeNull();
    expect(data.shopSeq).toBe("1");
    // الرصيد = 10000 − 4000 = 6000.
    expect(data.balanceAfter).toBe("6000");
  });

  it("يسجّل دفعة مرتبطة بعملية ويحسب الرصيد", async () => {
    const token = await registerAndLogin(OWNER_EMAIL);
    const shopId = await createShop(token, "محل دفع مرتبط");
    const customerId = await createCustomer(token, shopId);
    const purchaseId = await createPurchase(token, shopId, customerId, 5000, 0);

    const res = await app.inject({
      method: "POST",
      url: `/api/v1/shops/${shopId}/payments`,
      headers: { authorization: `Bearer ${token}` },
      payload: { customerId, purchaseId, amount: 2000 },
    });
    expect(res.statusCode).toBe(201);
    expect(res.json().data.purchaseId).toBe(purchaseId);
    expect(res.json().data.balanceAfter).toBe("3000");
  });

  it("يرفض المبلغ صفرًا أو سالبًا", async () => {
    const token = await registerAndLogin(OWNER_EMAIL);
    const shopId = await createShop(token, "محل مبلغ صفري");
    const customerId = await createCustomer(token, shopId);

    const zero = await app.inject({
      method: "POST",
      url: `/api/v1/shops/${shopId}/payments`,
      headers: { authorization: `Bearer ${token}` },
      payload: { customerId, amount: 0 },
    });
    expect(zero.statusCode).toBe(400);
    expect(zero.json().error.message_ar).toBe("بيانات الطلب غير صالحة.");

    const negative = await app.inject({
      method: "POST",
      url: `/api/v1/shops/${shopId}/payments`,
      headers: { authorization: `Bearer ${token}` },
      payload: { customerId, amount: -5 },
    });
    expect(negative.statusCode).toBe(400);
  });

  it("يرفض دفعة عامة تتجاوز رصيد العميل", async () => {
    const token = await registerAndLogin(OWNER_EMAIL);
    const shopId = await createShop(token, "محل تجاوز الرصيد");
    const customerId = await createCustomer(token, shopId);
    await createPurchase(token, shopId, customerId, 1000, 0);

    const res = await app.inject({
      method: "POST",
      url: `/api/v1/shops/${shopId}/payments`,
      headers: { authorization: `Bearer ${token}` },
      payload: { customerId, amount: 1500 },
    });
    expect(res.statusCode).toBe(400);
    expect(res.json().error.message_ar).toBe("المبلغ يتجاوز إجمالي المتبقي على العميل.");
  });

  it("يرفض دفعة مرتبطة تتجاوز متبقي العملية", async () => {
    const token = await registerAndLogin(OWNER_EMAIL);
    const shopId = await createShop(token, "محل تجاوز العملية");
    const customerId = await createCustomer(token, shopId);
    const purchaseId = await createPurchase(token, shopId, customerId, 3000, 1000);

    const res = await app.inject({
      method: "POST",
      url: `/api/v1/shops/${shopId}/payments`,
      headers: { authorization: `Bearer ${token}` },
      payload: { customerId, purchaseId, amount: 2500 },
    });
    expect(res.statusCode).toBe(400);
    expect(res.json().error.message_ar).toBe("المبلغ يتجاوز المتبقي على العملية.");
  });

  it("يرفض دفعة مرتبطة بعملية لعميل آخر", async () => {
    const token = await registerAndLogin(OWNER_EMAIL);
    const shopId = await createShop(token, "محل ربط خاطئ");
    const c1 = await createCustomer(token, shopId, "أحمد");
    const c2 = await createCustomer(token, shopId, "بدر");
    const purchaseId = await createPurchase(token, shopId, c1, 5000, 0);

    const res = await app.inject({
      method: "POST",
      url: `/api/v1/shops/${shopId}/payments`,
      headers: { authorization: `Bearer ${token}` },
      payload: { customerId: c2, purchaseId, amount: 1000 },
    });
    expect(res.statusCode).toBe(404);
  });

  it("يرفض عميلًا غير مرتبط بالمحل", async () => {
    const token = await registerAndLogin(OWNER_EMAIL);
    const shopId = await createShop(token, "محل أ");
    const otherToken = await registerAndLogin(OTHER_EMAIL);
    const otherShopId = await createShop(otherToken, "محل ب");
    const otherCustomer = await createCustomer(otherToken, otherShopId);

    const res = await app.inject({
      method: "POST",
      url: `/api/v1/shops/${shopId}/payments`,
      headers: { authorization: `Bearer ${token}` },
      payload: { customerId: otherCustomer, amount: 100 },
    });
    expect(res.statusCode).toBe(404);
  });

  it("يمنع تكرار الدفعة بنفس المعرّف الثابت (UUID)", async () => {
    const token = await registerAndLogin(OWNER_EMAIL);
    const shopId = await createShop(token, "محل تكرار دفعة");
    const customerId = await createCustomer(token, shopId);
    await createPurchase(token, shopId, customerId, 9000, 0);
    const fixedId = "01890000-0000-7000-8000-0000000000a1";

    const first = await app.inject({
      method: "POST",
      url: `/api/v1/shops/${shopId}/payments`,
      headers: { authorization: `Bearer ${token}` },
      payload: { id: fixedId, customerId, amount: 1000 },
    });
    expect(first.statusCode).toBe(201);

    const second = await app.inject({
      method: "POST",
      url: `/api/v1/shops/${shopId}/payments`,
      headers: { authorization: `Bearer ${token}` },
      payload: { id: fixedId, customerId, amount: 1000 },
    });
    expect(second.statusCode).toBe(201);
    expect(second.json().data.id).toBe(fixedId);

    const all = await db
      .select()
      .from(payments)
      .where(and(eq(payments.shopId, shopId), eq(payments.id, fixedId)));
    expect(all).toHaveLength(1);
  });

  it("يمنع تكرار الدفعة بنفس Idempotency-Key", async () => {
    const token = await registerAndLogin(OWNER_EMAIL);
    const shopId = await createShop(token, "محل مفتاح دفعة");
    const customerId = await createCustomer(token, shopId);
    await createPurchase(token, shopId, customerId, 9000, 0);

    const payload = { customerId, amount: 500 };
    const first = await app.inject({
      method: "POST",
      url: `/api/v1/shops/${shopId}/payments`,
      headers: { authorization: `Bearer ${token}`, "idempotency-key": "pay-key-1" },
      payload,
    });
    expect(first.statusCode).toBe(201);

    const second = await app.inject({
      method: "POST",
      url: `/api/v1/shops/${shopId}/payments`,
      headers: { authorization: `Bearer ${token}`, "idempotency-key": "pay-key-1" },
      payload,
    });
    expect(second.statusCode).toBe(201);
    expect(second.json().data.id).toBe(first.json().data.id);

    const rows = await db
      .select()
      .from(payments)
      .where(eq(payments.shopId, shopId));
    expect(rows).toHaveLength(1);
  });

  it("يزيد رقم الدفعة تسلسليًا ضمن المحل", async () => {
    const token = await registerAndLogin(OWNER_EMAIL);
    const shopId = await createShop(token, "محل تسلسل دفعة");
    const customerId = await createCustomer(token, shopId);
    await createPurchase(token, shopId, customerId, 9000, 0);

    const seqs: string[] = [];
    for (let i = 0; i < 3; i++) {
      const res = await app.inject({
        method: "POST",
        url: `/api/v1/shops/${shopId}/payments`,
        headers: { authorization: `Bearer ${token}` },
        payload: { customerId, amount: 100 },
      });
      seqs.push(res.json().data.shopSeq);
    }
    expect(seqs).toEqual(["1", "2", "3"]);
  });

  it("يعيد قائمة دفعات المحل ويفلتر بالعميل", async () => {
    const token = await registerAndLogin(OWNER_EMAIL);
    const shopId = await createShop(token, "محل قائمة دفعات");
    const c1 = await createCustomer(token, shopId, "عميل 1");
    const c2 = await createCustomer(token, shopId, "عميل 2");
    await createPurchase(token, shopId, c1, 9000, 0);
    await createPurchase(token, shopId, c2, 9000, 0);
    for (const cid of [c1, c1, c2]) {
      await app.inject({
        method: "POST",
        url: `/api/v1/shops/${shopId}/payments`,
        headers: { authorization: `Bearer ${token}` },
        payload: { customerId: cid, amount: 100 },
      });
    }

    const all = await app.inject({
      method: "GET",
      url: `/api/v1/shops/${shopId}/payments`,
      headers: { authorization: `Bearer ${token}` },
    });
    expect(all.json().data.items).toHaveLength(3);

    const filtered = await app.inject({
      method: "GET",
      url: `/api/v1/shops/${shopId}/payments?customerId=${c1}`,
      headers: { authorization: `Bearer ${token}` },
    });
    expect(filtered.json().data.items).toHaveLength(2);
  });

  it("يعيد تفاصيل دفعة", async () => {
    const token = await registerAndLogin(OWNER_EMAIL);
    const shopId = await createShop(token, "محل تفاصيل دفعة");
    const customerId = await createCustomer(token, shopId);
    await createPurchase(token, shopId, customerId, 9000, 0);
    const created = await app.inject({
      method: "POST",
      url: `/api/v1/shops/${shopId}/payments`,
      headers: { authorization: `Bearer ${token}` },
      payload: { customerId, amount: 777, notes: "دفعة نقدية" },
    });
    const id = created.json().data.id;

    const detail = await app.inject({
      method: "GET",
      url: `/api/v1/shops/${shopId}/payments/${id}`,
      headers: { authorization: `Bearer ${token}` },
    });
    expect(detail.statusCode).toBe(200);
    expect(detail.json().data.amount).toBe("777");
    expect(detail.json().data.notes).toBe("دفعة نقدية");
  });

  it("يعزل دفعات المحل عن محل آخر", async () => {
    const ownerToken = await registerAndLogin(OWNER_EMAIL);
    const shopId = await createShop(ownerToken, "محل خاص دفعة");
    const customerId = await createCustomer(ownerToken, shopId);
    await createPurchase(ownerToken, shopId, customerId, 9000, 0);
    const created = await app.inject({
      method: "POST",
      url: `/api/v1/shops/${shopId}/payments`,
      headers: { authorization: `Bearer ${ownerToken}` },
      payload: { customerId, amount: 50 },
    });
    const paymentId = created.json().data.id;

    const otherToken = await registerAndLogin(OTHER_EMAIL);
    const otherShopId = await createShop(otherToken, "محل آخر دفعة");

    const otherList = await app.inject({
      method: "GET",
      url: `/api/v1/shops/${otherShopId}/payments`,
      headers: { authorization: `Bearer ${otherToken}` },
    });
    expect(otherList.json().data.items).toHaveLength(0);

    const detail = await app.inject({
      method: "GET",
      url: `/api/v1/shops/${shopId}/payments/${paymentId}`,
      headers: { authorization: `Bearer ${otherToken}` },
    });
    expect(detail.statusCode).toBe(403);
  });
});

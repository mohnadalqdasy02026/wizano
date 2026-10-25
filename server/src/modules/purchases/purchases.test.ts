// اختبارات تكامل وحدة المشتريات الآجلة — على قاعدة wizano_test الحقيقية.
// تغطي: الإنشاء + المتبقي المشتق + رقم العملية الفريد + الدفعة المرتبطة،
// القيود المالية، رفض المدفوع > الإجمالي، منع التكرار (UUID/Idempotency-Key)،
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

const OWNER_EMAIL = "purch-test+owner@example.com";
const OTHER_EMAIL = "purch-test+other@example.com";
const PASSWORD = "PurchTest12345";

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

beforeAll(async () => {
  ({ db, client } = createDb());
  await migrate(db, { migrationsFolder });
  await cleanup();
  app = await buildApp({
    authDeps: { db },
    shopsDeps: { db },
    customersDeps: { db },
    purchasesDeps: { db },
  });
}, 60000);

afterAll(async () => {
  if (db) await cleanup();
  if (app) await app.close();
  if (client) await client.end({ timeout: 5 });
});

describe("وحدة المشتريات الآجلة", () => {
  it("يرفض الوصول بدون رمز مصادقة", async () => {
    const token = await registerAndLogin(OWNER_EMAIL);
    const shopId = await createShop(token, "محل الرفض");
    const res = await app.inject({
      method: "GET",
      url: `/api/v1/shops/${shopId}/purchases`,
    });
    expect(res.statusCode).toBe(401);
  });

  it("ينشئ عملية ويحسب المتبقي آليًا ورقم العملية الفريد", async () => {
    const token = await registerAndLogin(OWNER_EMAIL);
    const shopId = await createShop(token, "محل المشتريات");
    const customerId = await createCustomer(token, shopId, "أحمد");

    const res = await app.inject({
      method: "POST",
      url: `/api/v1/shops/${shopId}/purchases`,
      headers: { authorization: `Bearer ${token}` },
      payload: {
        customerId,
        itemsText: "أرز 2 كيس + سكر 1",
        totalAmount: 10000,
        paidAmount: 3000,
      },
    });
    expect(res.statusCode).toBe(201);
    const data = res.json().data;
    expect(data.totalAmount).toBe("10000");
    expect(data.paidAmount).toBe("3000");
    expect(data.remainingAmount).toBe("7000");
    expect(data.shopSeq).toBe("1");
    expect(data.status).toBe("active");
    // الرصيد بعد العملية = 10000 − 3000 = 7000.
    expect(data.balanceAfter).toBe("7000");

    // الدفعة المرتبطة بالعملية أُنشئت تلقائيًا (منع الحساب المزدوج).
    const linked = await db
      .select()
      .from(payments)
      .where(eq(payments.purchaseId, data.id));
    expect(linked).toHaveLength(1);
    expect(linked[0]?.amount).toBe(3000n);
  });

  it("ينشئ عملية مدفوعة كاملًا (متبقي 0، بلا دفعة)", async () => {
    const token = await registerAndLogin(OWNER_EMAIL);
    const shopId = await createShop(token, "محل مدفوع");
    const customerId = await createCustomer(token, shopId);

    const res = await app.inject({
      method: "POST",
      url: `/api/v1/shops/${shopId}/purchases`,
      headers: { authorization: `Bearer ${token}` },
      payload: {
        customerId,
        itemsText: "بضاعة",
        totalAmount: 5000,
        paidAmount: 5000,
      },
    });
    expect(res.statusCode).toBe(201);
    expect(res.json().data.remainingAmount).toBe("0");

    const linked = await db
      .select()
      .from(payments)
      .where(eq(payments.purchaseId, res.json().data.id));
    expect(linked).toHaveLength(1);
  });

  it("يرفض المدفوع أكبر من الإجمالي بخطأ عربي", async () => {
    const token = await registerAndLogin(OWNER_EMAIL);
    const shopId = await createShop(token, "محل الرفض المالي");
    const customerId = await createCustomer(token, shopId);

    const res = await app.inject({
      method: "POST",
      url: `/api/v1/shops/${shopId}/purchases`,
      headers: { authorization: `Bearer ${token}` },
      payload: {
        customerId,
        itemsText: "بضاعة",
        totalAmount: 1000,
        paidAmount: 2000,
      },
    });
    expect(res.statusCode).toBe(400);
    expect(res.json().error.message_ar).toBe("بيانات الطلب غير صالحة.");
  });

  it("يرفض الإجمالي السالب", async () => {
    const token = await registerAndLogin(OWNER_EMAIL);
    const shopId = await createShop(token, "محل السالب");
    const customerId = await createCustomer(token, shopId);

    const res = await app.inject({
      method: "POST",
      url: `/api/v1/shops/${shopId}/purchases`,
      headers: { authorization: `Bearer ${token}` },
      payload: {
        customerId,
        itemsText: "بضاعة",
        totalAmount: -1,
        paidAmount: 0,
      },
    });
    expect(res.statusCode).toBe(400);
  });

  it("يرفض عميلًا غير مرتبط بالمحل", async () => {
    const token = await registerAndLogin(OWNER_EMAIL);
    const shopId = await createShop(token, "محل أ");
    const otherToken = await registerAndLogin(OTHER_EMAIL);
    const otherShopId = await createShop(otherToken, "محل ب");
    const otherCustomer = await createCustomer(otherToken, otherShopId);

    const res = await app.inject({
      method: "POST",
      url: `/api/v1/shops/${shopId}/purchases`,
      headers: { authorization: `Bearer ${token}` },
      payload: {
        customerId: otherCustomer,
        itemsText: "بضاعة",
        totalAmount: 100,
        paidAmount: 0,
      },
    });
    expect(res.statusCode).toBe(404);
  });

  it("يمنع تكرار العملية بنفس المعرّف الثابت (UUID)", async () => {
    const token = await registerAndLogin(OWNER_EMAIL);
    const shopId = await createShop(token, "محل التكرار");
    const customerId = await createCustomer(token, shopId);
    const fixedId = "01890000-0000-7000-8000-000000000001";

    const first = await app.inject({
      method: "POST",
      url: `/api/v1/shops/${shopId}/purchases`,
      headers: { authorization: `Bearer ${token}` },
      payload: {
        id: fixedId,
        customerId,
        itemsText: "بضاعة",
        totalAmount: 1000,
        paidAmount: 0,
      },
    });
    expect(first.statusCode).toBe(201);

    const second = await app.inject({
      method: "POST",
      url: `/api/v1/shops/${shopId}/purchases`,
      headers: { authorization: `Bearer ${token}` },
      payload: {
        id: fixedId,
        customerId,
        itemsText: "بضاعة",
        totalAmount: 1000,
        paidAmount: 0,
      },
    });
    expect(second.statusCode).toBe(201);
    expect(second.json().data.id).toBe(fixedId);

    const all = await db
      .select()
      .from(purchases)
      .where(and(eq(purchases.shopId, shopId), eq(purchases.id, fixedId)));
    expect(all).toHaveLength(1);
  });

  it("يمنع تكرار العملية بنفس Idempotency-Key", async () => {
    const token = await registerAndLogin(OWNER_EMAIL);
    const shopId = await createShop(token, "محل المفتاح");
    const customerId = await createCustomer(token, shopId);

    const payload = {
      customerId,
      itemsText: "بضاعة",
      totalAmount: 2000,
      paidAmount: 500,
    };
    const first = await app.inject({
      method: "POST",
      url: `/api/v1/shops/${shopId}/purchases`,
      headers: {
        authorization: `Bearer ${token}`,
        "idempotency-key": "key-abc-123",
      },
      payload,
    });
    expect(first.statusCode).toBe(201);

    const second = await app.inject({
      method: "POST",
      url: `/api/v1/shops/${shopId}/purchases`,
      headers: {
        authorization: `Bearer ${token}`,
        "idempotency-key": "key-abc-123",
      },
      payload,
    });
    expect(second.statusCode).toBe(201);
    expect(second.json().data.id).toBe(first.json().data.id);

    const rows = await db
      .select()
      .from(purchases)
      .where(eq(purchases.shopId, shopId));
    expect(rows).toHaveLength(1);
  });

  it("يزيد رقم العملية تسلسليًا ضمن المحل", async () => {
    const token = await registerAndLogin(OWNER_EMAIL);
    const shopId = await createShop(token, "محل التسلسل");
    const customerId = await createCustomer(token, shopId);

    const seqs: string[] = [];
    for (let i = 0; i < 3; i++) {
      const res = await app.inject({
        method: "POST",
        url: `/api/v1/shops/${shopId}/purchases`,
        headers: { authorization: `Bearer ${token}` },
        payload: {
          customerId,
          itemsText: `بضاعة ${i}`,
          totalAmount: 100,
          paidAmount: 0,
        },
      });
      seqs.push(res.json().data.shopSeq);
    }
    expect(seqs).toEqual(["1", "2", "3"]);
  });

  it("يعيد قائمة مشتريات المحل ويفلتر بالعميل", async () => {
    const token = await registerAndLogin(OWNER_EMAIL);
    const shopId = await createShop(token, "محل القائمة");
    const c1 = await createCustomer(token, shopId, "عميل 1");
    const c2 = await createCustomer(token, shopId, "عميل 2");
    for (const cid of [c1, c1, c2]) {
      await app.inject({
        method: "POST",
        url: `/api/v1/shops/${shopId}/purchases`,
        headers: { authorization: `Bearer ${token}` },
        payload: { customerId: cid, itemsText: "بضاعة", totalAmount: 10, paidAmount: 0 },
      });
    }

    const all = await app.inject({
      method: "GET",
      url: `/api/v1/shops/${shopId}/purchases`,
      headers: { authorization: `Bearer ${token}` },
    });
    expect(all.json().data.items).toHaveLength(3);

    const filtered = await app.inject({
      method: "GET",
      url: `/api/v1/shops/${shopId}/purchases?customerId=${c1}`,
      headers: { authorization: `Bearer ${token}` },
    });
    expect(filtered.json().data.items).toHaveLength(2);
  });

  it("يعيد تفاصيل عملية", async () => {
    const token = await registerAndLogin(OWNER_EMAIL);
    const shopId = await createShop(token, "محل التفاصيل");
    const customerId = await createCustomer(token, shopId);
    const created = await app.inject({
      method: "POST",
      url: `/api/v1/shops/${shopId}/purchases`,
      headers: { authorization: `Bearer ${token}` },
      payload: { customerId, itemsText: "تفاصيل", totalAmount: 999, paidAmount: 111 },
    });
    const id = created.json().data.id;

    const detail = await app.inject({
      method: "GET",
      url: `/api/v1/shops/${shopId}/purchases/${id}`,
      headers: { authorization: `Bearer ${token}` },
    });
    expect(detail.statusCode).toBe(200);
    expect(detail.json().data.itemsText).toBe("تفاصيل");
    expect(detail.json().data.remainingAmount).toBe("888");
  });

  it("يعزل مشتريات المحل عن محل آخر", async () => {
    const ownerToken = await registerAndLogin(OWNER_EMAIL);
    const shopId = await createShop(ownerToken, "محل خاص");
    const customerId = await createCustomer(ownerToken, shopId);
    const created = await app.inject({
      method: "POST",
      url: `/api/v1/shops/${shopId}/purchases`,
      headers: { authorization: `Bearer ${ownerToken}` },
      payload: { customerId, itemsText: "خاصة", totalAmount: 50, paidAmount: 0 },
    });
    const purchaseId = created.json().data.id;

    const otherToken = await registerAndLogin(OTHER_EMAIL);
    const otherShopId = await createShop(otherToken, "محل آخر");

    const otherList = await app.inject({
      method: "GET",
      url: `/api/v1/shops/${otherShopId}/purchases`,
      headers: { authorization: `Bearer ${otherToken}` },
    });
    expect(otherList.json().data.items).toHaveLength(0);

    const detail = await app.inject({
      method: "GET",
      url: `/api/v1/shops/${shopId}/purchases/${purchaseId}`,
      headers: { authorization: `Bearer ${otherToken}` },
    });
    expect(detail.statusCode).toBe(403);
  });
});

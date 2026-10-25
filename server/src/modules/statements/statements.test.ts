// اختبارات تكامل وحدة كشف الحساب — على قاعدة wizano_test الحقيقية.
// تغطي: تجميع المشتريات والمدفوعات زمنيًا، الرصيد الجاري بعد كل عملية، الإجماليات،
// تطابق الرصيد النهائي مع القيمة المخزَّنة، التصفية بالنوع والتاريخ، والعزل بين المحلات.

import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { inArray } from "drizzle-orm";
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

const OWNER_EMAIL = "stmt-test+owner@example.com";
const OTHER_EMAIL = "stmt-test+other@example.com";
const PASSWORD = "StmtTest12345";

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
  occurredAt?: string,
): Promise<string> {
  const res = await app.inject({
    method: "POST",
    url: `/api/v1/shops/${shopId}/purchases`,
    headers: { authorization: `Bearer ${token}` },
    payload: {
      customerId,
      itemsText: "بضاعة",
      totalAmount: total,
      paidAmount: paid,
      ...(occurredAt ? { occurredAt } : {}),
    },
  });
  return res.json().data.id;
}

async function createPayment(
  token: string,
  shopId: string,
  customerId: string,
  amount: number,
  paidAt?: string,
): Promise<void> {
  await app.inject({
    method: "POST",
    url: `/api/v1/shops/${shopId}/payments`,
    headers: { authorization: `Bearer ${token}` },
    payload: { customerId, amount, ...(paidAt ? { paidAt } : {}) },
  });
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
    statementsDeps: { db },
  });
}, 60000);

afterAll(async () => {
  if (db) await cleanup();
  if (app) await app.close();
  if (client) await client.end({ timeout: 5 });
});

describe("وحدة كشف الحساب", () => {
  it("يرفض الوصول بدون رمز مصادقة", async () => {
    const token = await registerAndLogin(OWNER_EMAIL);
    const shopId = await createShop(token, "محل رفض كشف");
    const customerId = await createCustomer(token, shopId);
    const res = await app.inject({
      method: "GET",
      url: `/api/v1/shops/${shopId}/customers/${customerId}/statement`,
    });
    expect(res.statusCode).toBe(401);
  });

  it("يجمع العمليات زمنيًا مع رصيد جارٍ صحيح وإجماليات", async () => {
    const token = await registerAndLogin(OWNER_EMAIL);
    const shopId = await createShop(token, "محل كشف كامل");
    const customerId = await createCustomer(token, shopId, "سالم");

    // ترتيب زمني واضح: شراء (10000) ثم دفعة (4000) ثم شراء (5000).
    await createPurchase(token, shopId, customerId, 10000, 0,
      "2026-01-01T10:00:00.000Z");
    await createPayment(token, shopId, customerId, 4000, "2026-01-02T10:00:00.000Z");
    await createPurchase(token, shopId, customerId, 5000, 0,
      "2026-01-03T10:00:00.000Z");

    const res = await app.inject({
      method: "GET",
      url: `/api/v1/shops/${shopId}/customers/${customerId}/statement`,
      headers: { authorization: `Bearer ${token}` },
    });
    expect(res.statusCode).toBe(200);
    const data = res.json().data;

    expect(data.totalPurchases).toBe("15000");
    expect(data.totalPayments).toBe("4000");
    expect(data.balance).toBe("11000");

    expect(data.entries).toHaveLength(3);
    expect(data.entries.map((e: { type: string }) => e.type)).toEqual([
      "purchase",
      "payment",
      "purchase",
    ]);
    expect(data.entries[0].effect).toBe("10000");
    expect(data.entries[0].balanceAfter).toBe("10000");
    expect(data.entries[1].effect).toBe("-4000");
    expect(data.entries[1].balanceAfter).toBe("6000");
    expect(data.entries[2].effect).toBe("5000");
    expect(data.entries[2].balanceAfter).toBe("11000");
  });

  it("يطابق الرصيد النهائي في الكشف الرصيد المخزَّن على آخر عملية", async () => {
    const token = await registerAndLogin(OWNER_EMAIL);
    const shopId = await createShop(token, "محل مطابقة الرصيد");
    const customerId = await createCustomer(token, shopId);

    await createPurchase(token, shopId, customerId, 7000, 2000,
      "2026-02-01T10:00:00.000Z");
    await createPayment(token, shopId, customerId, 1000, "2026-02-02T10:00:00.000Z");

    const res = await app.inject({
      method: "GET",
      url: `/api/v1/shops/${shopId}/customers/${customerId}/statement`,
      headers: { authorization: `Bearer ${token}` },
    });
    const data = res.json().data;
    // الرصيد = 7000 − 2000 − 1000 = 4000.
    expect(data.balance).toBe("4000");
    const last = data.entries[data.entries.length - 1];
    expect(last.balanceAfter).toBe("4000");
  });

  it("يفلتر حسب النوع دون الإخلال بإجماليات الرصيد", async () => {
    const token = await registerAndLogin(OWNER_EMAIL);
    const shopId = await createShop(token, "محل فلترة نوع");
    const customerId = await createCustomer(token, shopId);
    await createPurchase(token, shopId, customerId, 10000, 0,
      "2026-03-01T10:00:00.000Z");
    await createPayment(token, shopId, customerId, 3000, "2026-03-02T10:00:00.000Z");

    const onlyPayments = await app.inject({
      method: "GET",
      url: `/api/v1/shops/${shopId}/customers/${customerId}/statement?type=payment`,
      headers: { authorization: `Bearer ${token}` },
    });
    const data = onlyPayments.json().data;
    expect(data.entries).toHaveLength(1);
    expect(data.entries[0].type).toBe("payment");
    // الرصيد الجاري يعكس كل التاريخ: 10000 − 3000 = 7000 بعد الدفعة.
    expect(data.entries[0].balanceAfter).toBe("7000");
    // الإجماليات الكاملة تبقى ثابتة.
    expect(data.totalPurchases).toBe("10000");
    expect(data.totalPayments).toBe("3000");
    expect(data.balance).toBe("7000");
  });

  it("يفلتر حسب نطاق التاريخ", async () => {
    const token = await registerAndLogin(OWNER_EMAIL);
    const shopId = await createShop(token, "محل فلترة تاريخ");
    const customerId = await createCustomer(token, shopId);
    await createPurchase(token, shopId, customerId, 1000, 0,
      "2026-04-01T10:00:00.000Z");
    await createPurchase(token, shopId, customerId, 2000, 0,
      "2026-04-15T10:00:00.000Z");
    await createPurchase(token, shopId, customerId, 3000, 0,
      "2026-04-30T10:00:00.000Z");

    const res = await app.inject({
      method: "GET",
      url: `/api/v1/shops/${shopId}/customers/${customerId}/statement?from=2026-04-10T00:00:00.000Z&to=2026-04-20T00:00:00.000Z`,
      headers: { authorization: `Bearer ${token}` },
    });
    const data = res.json().data;
    expect(data.entries).toHaveLength(1);
    expect(data.entries[0].effect).toBe("2000");
    // الرصيد الجاري يشمل العملية الأولى: 1000 + 2000 = 3000.
    expect(data.entries[0].balanceAfter).toBe("3000");
    expect(data.balance).toBe("6000");
  });

  it("يشمل الدفعات المرتبطة بعملية الشراء في الكشف", async () => {
    const token = await registerAndLogin(OWNER_EMAIL);
    const shopId = await createShop(token, "محل كشف دفعة مرتبطة");
    const customerId = await createCustomer(token, shopId);
    await createPurchase(token, shopId, customerId, 8000, 3000,
      "2026-05-01T10:00:00.000Z");

    const res = await app.inject({
      method: "GET",
      url: `/api/v1/shops/${shopId}/customers/${customerId}/statement`,
      headers: { authorization: `Bearer ${token}` },
    });
    const data = res.json().data;
    // سطران: شراء ثم دفعة وقت الشراء (نفس الوقت ⇒ الشراء أولًا).
    expect(data.entries).toHaveLength(2);
    expect(data.entries[0].type).toBe("purchase");
    expect(data.entries[1].type).toBe("payment");
    expect(data.entries[1].purchaseId).toBe(data.entries[0].id);
    expect(data.balance).toBe("5000");
  });

  it("يرفض عميلًا غير مرتبط بالمحل (404)", async () => {
    const token = await registerAndLogin(OWNER_EMAIL);
    const shopId = await createShop(token, "محل أ كشف");
    const otherToken = await registerAndLogin(OTHER_EMAIL);
    const otherShopId = await createShop(otherToken, "محل ب كشف");
    const otherCustomer = await createCustomer(otherToken, otherShopId);

    const res = await app.inject({
      method: "GET",
      url: `/api/v1/shops/${shopId}/customers/${otherCustomer}/statement`,
      headers: { authorization: `Bearer ${token}` },
    });
    expect(res.statusCode).toBe(404);
  });

  it("يعزل كشف المحل عن محل آخر (403)", async () => {
    const ownerToken = await registerAndLogin(OWNER_EMAIL);
    const shopId = await createShop(ownerToken, "محل خاص كشف");
    const customerId = await createCustomer(ownerToken, shopId);
    await createPurchase(ownerToken, shopId, customerId, 1000, 0);

    const otherToken = await registerAndLogin(OTHER_EMAIL);
    const res = await app.inject({
      method: "GET",
      url: `/api/v1/shops/${shopId}/customers/${customerId}/statement`,
      headers: { authorization: `Bearer ${otherToken}` },
    });
    expect(res.statusCode).toBe(403);
  });

  it("يعيد كشفًا فارغًا لعميل بلا عمليات", async () => {
    const token = await registerAndLogin(OWNER_EMAIL);
    const shopId = await createShop(token, "محل كشف فارغ");
    const customerId = await createCustomer(token, shopId);

    const res = await app.inject({
      method: "GET",
      url: `/api/v1/shops/${shopId}/customers/${customerId}/statement`,
      headers: { authorization: `Bearer ${token}` },
    });
    expect(res.statusCode).toBe(200);
    const data = res.json().data;
    expect(data.entries).toHaveLength(0);
    expect(data.balance).toBe("0");
  });
});

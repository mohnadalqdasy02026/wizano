// اختبارات تكامل المرحلة 11 — المرتجعات والتصحيحات المالية والإلغاءات وسجل التدقيق.
// على قاعدة wizano_test الحقيقية. تغطي: القيود المالية، أثر الرصيد، التدقيق، والعزل.

import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { inArray } from "drizzle-orm";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { migrate } from "drizzle-orm/postgres-js/migrator";
import { buildApp } from "../../app.js";
import { createDb, type Database, type SqlClient } from "../../db/index.js";
import {
  auditLogs,
  customerShopLinks,
  customers,
  financialAdjustments,
  payments,
  purchaseReturns,
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

const OWNER_EMAIL = "ret-test+owner@example.com";
const OTHER_EMAIL = "ret-test+other@example.com";
const PASSWORD = "RetTest12345";

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
    // سجل التدقيق غير قابل للحذف عبر trigger؛ نعطّله مؤقتًا أثناء التنظيف فقط.
    await client`ALTER TABLE public.audit_logs DISABLE TRIGGER audit_logs_immutable`;
    await db.delete(auditLogs).where(inArray(auditLogs.shopId, shopIds));
    await client`ALTER TABLE public.audit_logs ENABLE TRIGGER audit_logs_immutable`;
    await db.delete(syncOperations).where(inArray(syncOperations.shopId, shopIds));
    await db
      .delete(financialAdjustments)
      .where(inArray(financialAdjustments.shopId, shopIds));
    await db.delete(purchaseReturns).where(inArray(purchaseReturns.shopId, shopIds));
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

async function statement(token: string, shopId: string, customerId: string) {
  const res = await app.inject({
    method: "GET",
    url: `/api/v1/shops/${shopId}/customers/${customerId}/statement`,
    headers: { authorization: `Bearer ${token}` },
  });
  return res.json().data;
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
    returnsDeps: { db },
    adjustmentsDeps: { db },
    auditDeps: { db },
  });
}, 60000);

afterAll(async () => {
  if (db) await cleanup();
  if (app) await app.close();
  if (client) await client.end({ timeout: 5 });
});

describe("المرتجعات", () => {
  it("يسجّل مرتجعًا ويخصم من الرصيد مع توثيق تدقيقي", async () => {
    const token = await registerAndLogin(OWNER_EMAIL);
    const shopId = await createShop(token, "محل مرتجع");
    const customerId = await createCustomer(token, shopId, "سالم");
    const purchaseId = await createPurchase(token, shopId, customerId, 10000, 3000);

    const res = await app.inject({
      method: "POST",
      url: `/api/v1/shops/${shopId}/returns`,
      headers: { authorization: `Bearer ${token}` },
      payload: { purchaseId, amount: 2000, reason: "بضاعة تالفة" },
    });
    expect(res.statusCode).toBe(201);
    const created = res.json().data;
    expect(created.amount).toBe("2000");
    // الرصيد = 10000 − 3000 − 2000 = 5000.
    expect(created.balanceAfter).toBe("5000");

    const st = await statement(token, shopId, customerId);
    expect(st.totalReturns).toBe("2000");
    expect(st.balance).toBe("5000");

    const audit = await db
      .select()
      .from(auditLogs)
      .where(inArray(auditLogs.shopId, [shopId]));
    expect(audit.some((a) => a.action === "purchase.return")).toBe(true);
  });

  it("يرفض مرتجعًا يتجاوز متبقي العملية", async () => {
    const token = await registerAndLogin(OWNER_EMAIL);
    const shopId = await createShop(token, "محل تجاوز مرتجع");
    const customerId = await createCustomer(token, shopId);
    const purchaseId = await createPurchase(token, shopId, customerId, 5000, 1000);

    const res = await app.inject({
      method: "POST",
      url: `/api/v1/shops/${shopId}/returns`,
      headers: { authorization: `Bearer ${token}` },
      payload: { purchaseId, amount: 4500 },
    });
    // المتبقي = 5000 − 1000 = 4000؛ 4500 > 4000 ⇒ 400.
    expect(res.statusCode).toBe(400);
  });

  it("يمنع المرتجع على عملية ملغاة", async () => {
    const token = await registerAndLogin(OWNER_EMAIL);
    const shopId = await createShop(token, "محل مرتجع ملغى");
    const customerId = await createCustomer(token, shopId);
    const purchaseId = await createPurchase(token, shopId, customerId, 3000, 0);
    await app.inject({
      method: "POST",
      url: `/api/v1/shops/${shopId}/purchases/${purchaseId}/cancel`,
      headers: { authorization: `Bearer ${token}` },
      payload: { reason: "خطأ إدخال" },
    });
    const res = await app.inject({
      method: "POST",
      url: `/api/v1/shops/${shopId}/returns`,
      headers: { authorization: `Bearer ${token}` },
      payload: { purchaseId, amount: 100 },
    });
    // الإلغاء يستنفد المتعلق؛ المرتجع يتجاوز المتبقي ⇒ 400.
    expect(res.statusCode).toBe(400);
  });

  it("يعزل مرتجع المحل عن محل آخر (403)", async () => {
    const ownerToken = await registerAndLogin(OWNER_EMAIL);
    const shopId = await createShop(ownerToken, "محل مرتجع خاص");
    const customerId = await createCustomer(ownerToken, shopId);
    const purchaseId = await createPurchase(ownerToken, shopId, customerId, 1000, 0);

    const otherToken = await registerAndLogin(OTHER_EMAIL);
    const res = await app.inject({
      method: "POST",
      url: `/api/v1/shops/${shopId}/returns`,
      headers: { authorization: `Bearer ${otherToken}` },
      payload: { purchaseId, amount: 100 },
    });
    expect(res.statusCode).toBe(403);
  });
});

describe("التصحيحات المالية", () => {
  it("تصحيح موجب يزيد الرصيد مع سبب إلزامي", async () => {
    const token = await registerAndLogin(OWNER_EMAIL);
    const shopId = await createShop(token, "محل تصحيح موجب");
    const customerId = await createCustomer(token, shopId);
    await createPurchase(token, shopId, customerId, 5000, 0);

    const res = await app.inject({
      method: "POST",
      url: `/api/v1/shops/${shopId}/adjustments`,
      headers: { authorization: `Bearer ${token}` },
      payload: { customerId, amount: 500, reason: "تصحيح تسعير" },
    });
    expect(res.statusCode).toBe(201);
    expect(res.json().data.amount).toBe("500");
    expect(res.json().data.balanceAfter).toBe("5500");

    const st = await statement(token, shopId, customerId);
    expect(st.totalAdjustments).toBe("500");
    expect(st.balance).toBe("5500");
  });

  it("تصحيح سالب يخصم من الرصيد", async () => {
    const token = await registerAndLogin(OWNER_EMAIL);
    const shopId = await createShop(token, "محل تصحيح سالب");
    const customerId = await createCustomer(token, shopId);
    await createPurchase(token, shopId, customerId, 5000, 0);

    const res = await app.inject({
      method: "POST",
      url: `/api/v1/shops/${shopId}/adjustments`,
      headers: { authorization: `Bearer ${token}` },
      payload: { customerId, amount: -1200, reason: "خصم إداري" },
    });
    expect(res.statusCode).toBe(201);
    expect(res.json().data.balanceAfter).toBe("3800");
  });

  it("يرفض تصحيحًا بلا سبب", async () => {
    const token = await registerAndLogin(OWNER_EMAIL);
    const shopId = await createShop(token, "محل تصحيح بلا سبب");
    const customerId = await createCustomer(token, shopId);
    const res = await app.inject({
      method: "POST",
      url: `/api/v1/shops/${shopId}/adjustments`,
      headers: { authorization: `Bearer ${token}` },
      payload: { customerId, amount: 100, reason: "" },
    });
    expect(res.statusCode).toBe(400);
  });

  it("يرفض تصحيحًا بمبلغ صفر", async () => {
    const token = await registerAndLogin(OWNER_EMAIL);
    const shopId = await createShop(token, "محل تصحيح صفر");
    const customerId = await createCustomer(token, shopId);
    const res = await app.inject({
      method: "POST",
      url: `/api/v1/shops/${shopId}/adjustments`,
      headers: { authorization: `Bearer ${token}` },
      payload: { customerId, amount: 0, reason: "صفر" },
    });
    expect(res.statusCode).toBe(400);
  });

  it("يرفض تصحيحًا سالبًا يتجاوز الرصيد", async () => {
    const token = await registerAndLogin(OWNER_EMAIL);
    const shopId = await createShop(token, "محل تصحيح تجاوز");
    const customerId = await createCustomer(token, shopId);
    await createPurchase(token, shopId, customerId, 1000, 0);
    const res = await app.inject({
      method: "POST",
      url: `/api/v1/shops/${shopId}/adjustments`,
      headers: { authorization: `Bearer ${token}` },
      payload: { customerId, amount: -5000, reason: "خصم كبير" },
    });
    expect(res.statusCode).toBe(400);
  });
});

describe("إلغاء العمليات", () => {
  it("ينشئ قيدًا عكسيًا وصفّر مساهمة العملية مع بقاء الأصل كما هو", async () => {
    const token = await registerAndLogin(OWNER_EMAIL);
    const shopId = await createShop(token, "محل إلغاء");
    const customerId = await createCustomer(token, shopId);
    const purchaseId = await createPurchase(token, shopId, customerId, 7000, 2000);

    const res = await app.inject({
      method: "POST",
      url: `/api/v1/shops/${shopId}/purchases/${purchaseId}/cancel`,
      headers: { authorization: `Bearer ${token}` },
      payload: { reason: "عملية مكررة" },
    });
    expect(res.statusCode).toBe(201);
    const adjustment = res.json().data;
    expect(adjustment.kind).toBe("cancellation");
    // الأثر المتبقي = 7000 − 2000 = 5000 ⇒ القيد العكسي = −5000.
    expect(adjustment.amount).toBe("-5000");
    // الرصيد يعود صفرًا (العملية أُبطلت).
    expect(adjustment.balanceAfter).toBe("0");

    // الأصل يبقى كما هو (active، بالنفس القيم).
    const purchaseRow = await db
      .select()
      .from(purchases)
      .where(inArray(purchases.id, [purchaseId]));
    expect(purchaseRow[0]?.status).toBe("active");
    expect(purchaseRow[0]?.totalAmount).toBe(7000n);

    const audit = await db
      .select()
      .from(auditLogs)
      .where(inArray(auditLogs.shopId, [shopId]));
    expect(audit.some((a) => a.action === "purchase.cancel")).toBe(true);
  });

  it("يمنع الإلغاء المزدوج", async () => {
    const token = await registerAndLogin(OWNER_EMAIL);
    const shopId = await createShop(token, "محل إلغاء مزدوج");
    const customerId = await createCustomer(token, shopId);
    const purchaseId = await createPurchase(token, shopId, customerId, 4000, 0);
    await app.inject({
      method: "POST",
      url: `/api/v1/shops/${shopId}/purchases/${purchaseId}/cancel`,
      headers: { authorization: `Bearer ${token}` },
      payload: { reason: "أول" },
    });
    const second = await app.inject({
      method: "POST",
      url: `/api/v1/shops/${shopId}/purchases/${purchaseId}/cancel`,
      headers: { authorization: `Bearer ${token}` },
      payload: { reason: "ثانٍ" },
    });
    expect(second.statusCode).toBe(400);
  });

  it("يظهر سطرا الشراء والإلغاء في كشف الحساب بالرصيد الصحيح", async () => {
    const token = await registerAndLogin(OWNER_EMAIL);
    const shopId = await createShop(token, "محل كشف إلغاء");
    const customerId = await createCustomer(token, shopId);
    const purchaseId = await createPurchase(token, shopId, customerId, 6000, 0);
    await app.inject({
      method: "POST",
      url: `/api/v1/shops/${shopId}/purchases/${purchaseId}/cancel`,
      headers: { authorization: `Bearer ${token}` },
      payload: { reason: "إلغاء" },
    });

    const st = await statement(token, shopId, customerId);
    expect(st.balance).toBe("0");
    const types = st.entries.map((e: { type: string }) => e.type);
    expect(types).toContain("purchase");
    expect(types).toContain("adjustment");
    const adj = st.entries.find((e: { type: string }) => e.type === "adjustment");
    expect(adj.effect).toBe("-6000");
    expect(adj.balanceAfter).toBe("0");
  });
});

describe("سجل التدقيق", () => {
  it("يعيد إجراءات المحل المالية مع قبل/بعد", async () => {
    const token = await registerAndLogin(OWNER_EMAIL);
    const shopId = await createShop(token, "محل تدقيق");
    const customerId = await createCustomer(token, shopId);
    const purchaseId = await createPurchase(token, shopId, customerId, 3000, 0);
    await app.inject({
      method: "POST",
      url: `/api/v1/shops/${shopId}/returns`,
      headers: { authorization: `Bearer ${token}` },
      payload: { purchaseId, amount: 500, reason: "مرتجع" },
    });

    const res = await app.inject({
      method: "GET",
      url: `/api/v1/shops/${shopId}/audit-logs`,
      headers: { authorization: `Bearer ${token}` },
    });
    expect(res.statusCode).toBe(200);
    const items = res.json().data.items;
    expect(items.length).toBeGreaterThanOrEqual(1);
    expect(items[0].action).toBe("purchase.return");
    expect(items[0].after).toBeTruthy();
  });

  it("يعزل سجل التدقيق بين المحلات (403)", async () => {
    const ownerToken = await registerAndLogin(OWNER_EMAIL);
    const shopId = await createShop(ownerToken, "محل تدقيق خاص");
    const otherToken = await registerAndLogin(OTHER_EMAIL);
    const res = await app.inject({
      method: "GET",
      url: `/api/v1/shops/${shopId}/audit-logs`,
      headers: { authorization: `Bearer ${otherToken}` },
    });
    expect(res.statusCode).toBe(403);
  });
});

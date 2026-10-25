// اختبارات تكامل وحدة العملاء — على قاعدة wizano_test الحقيقية.
// تغطي: إنشاء عميل + ربطه بالمحل، القائمة والبحث، التفاصيل، التعديل، الأرشفة،
// عزل العملاء بين المحلات، وإنشاء رمز الدعوة.

import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { eq, inArray } from "drizzle-orm";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { migrate } from "drizzle-orm/postgres-js/migrator";
import { buildApp } from "../../app.js";
import { createDb, type Database, type SqlClient } from "../../db/index.js";
import {
  customers,
  customerShopLinks,
  invitations,
  refreshTokens,
  shopCounters,
  shopMembers,
  shops,
  users,
} from "../../db/schema.js";

const migrationsFolder = path.join(
  path.dirname(fileURLToPath(import.meta.url)),
  "../../db/migrations",
);

const OWNER_EMAIL = "cust-test+owner@example.com";
const OTHER_EMAIL = "cust-test+other@example.com";
const PASSWORD = "CustTest12345";

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
    const linkRows = await db
      .select({ customerId: customerShopLinks.customerId })
      .from(customerShopLinks)
      .where(inArray(customerShopLinks.shopId, shopIds));
    const customerIds = [...new Set(linkRows.map((l) => l.customerId))];

    await db.delete(invitations).where(inArray(invitations.shopId, shopIds));
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

beforeAll(async () => {
  ({ db, client } = createDb());
  await migrate(db, { migrationsFolder });
  await cleanup();
  app = await buildApp({
    authDeps: { db },
    shopsDeps: { db },
    customersDeps: { db },
  });
}, 60000);

afterAll(async () => {
  if (db) await cleanup();
  if (app) await app.close();
  if (client) await client.end({ timeout: 5 });
});

describe("وحدة العملاء", () => {
  it("يرفض الوصول بدون رمز مصادقة", async () => {
    const token = await registerAndLogin(OWNER_EMAIL);
    const shopId = await createShop(token, "محل للرفض");
    const res = await app.inject({
      method: "GET",
      url: `/api/v1/shops/${shopId}/customers`,
    });
    expect(res.statusCode).toBe(401);
  });

  it("ينشئ عميلًا ويربطه بالمحل", async () => {
    const token = await registerAndLogin(OWNER_EMAIL);
    const shopId = await createShop(token, "محل العملاء");
    const res = await app.inject({
      method: "POST",
      url: `/api/v1/shops/${shopId}/customers`,
      headers: { authorization: `Bearer ${token}` },
      payload: { displayName: "أحمد السامعي", phone: "777123456" },
    });
    expect(res.statusCode).toBe(201);
    const customer = res.json().data;
    expect(customer.displayName).toBe("أحمد السامعي");
    expect(customer.phone).toBe("777123456");

    const links = await db
      .select()
      .from(customerShopLinks)
      .where(eq(customerShopLinks.customerId, customer.id));
    expect(links).toHaveLength(1);
    expect(links[0]?.shopId).toBe(shopId);
    expect(links[0]?.status).toBe("active");
  });

  it("يرفض اسم عميل قصيرًا بخطأ عربي", async () => {
    const token = await registerAndLogin(OWNER_EMAIL);
    const shopId = await createShop(token, "محل الرفض");
    const res = await app.inject({
      method: "POST",
      url: `/api/v1/shops/${shopId}/customers`,
      headers: { authorization: `Bearer ${token}` },
      payload: { displayName: "أ" },
    });
    expect(res.statusCode).toBe(400);
    expect(res.json().error.message_ar).toBe("بيانات الطلب غير صالحة.");
  });

  it("يعيد عملاء المحل ويدعم البحث بالاسم", async () => {
    const token = await registerAndLogin(OWNER_EMAIL);
    const shopId = await createShop(token, "محل البحث");
    for (const name of ["سالم", "ناصر", "سعيد"]) {
      await app.inject({
        method: "POST",
        url: `/api/v1/shops/${shopId}/customers`,
        headers: { authorization: `Bearer ${token}` },
        payload: { displayName: name },
      });
    }

    const all = await app.inject({
      method: "GET",
      url: `/api/v1/shops/${shopId}/customers`,
      headers: { authorization: `Bearer ${token}` },
    });
    expect(all.json().data.items).toHaveLength(3);

    const filtered = await app.inject({
      method: "GET",
      url: `/api/v1/shops/${shopId}/customers?search=س`,
      headers: { authorization: `Bearer ${token}` },
    });
    expect(filtered.json().data.items.length).toBeGreaterThanOrEqual(2);
    expect(
      filtered.json().data.items.every((c: { displayName: string }) =>
        c.displayName.includes("س"),
      ),
    ).toBe(true);
  });

  it("يعيد تفاصيل عميل ويحدّث بياناته", async () => {
    const token = await registerAndLogin(OWNER_EMAIL);
    const shopId = await createShop(token, "محل التفاصيل");
    const created = await app.inject({
      method: "POST",
      url: `/api/v1/shops/${shopId}/customers`,
      headers: { authorization: `Bearer ${token}` },
      payload: { displayName: "اسم قديم" },
    });
    const customerId = created.json().data.id;

    const detail = await app.inject({
      method: "GET",
      url: `/api/v1/shops/${shopId}/customers/${customerId}`,
      headers: { authorization: `Bearer ${token}` },
    });
    expect(detail.statusCode).toBe(200);

    const updated = await app.inject({
      method: "PATCH",
      url: `/api/v1/shops/${shopId}/customers/${customerId}`,
      headers: { authorization: `Bearer ${token}` },
      payload: { displayName: "اسم جديد", notes: "ملاحظة" },
    });
    expect(updated.statusCode).toBe(200);
    expect(updated.json().data.displayName).toBe("اسم جديد");
    expect(updated.json().data.notes).toBe("ملاحظة");
  });

  it("يؤرشف عميلًا فيختفي من القائمة", async () => {
    const token = await registerAndLogin(OWNER_EMAIL);
    const shopId = await createShop(token, "محل الأرشفة");
    const created = await app.inject({
      method: "POST",
      url: `/api/v1/shops/${shopId}/customers`,
      headers: { authorization: `Bearer ${token}` },
      payload: { displayName: "للأرشفة" },
    });
    const customerId = created.json().data.id;

    const del = await app.inject({
      method: "DELETE",
      url: `/api/v1/shops/${shopId}/customers/${customerId}`,
      headers: { authorization: `Bearer ${token}` },
    });
    expect(del.statusCode).toBe(204);

    const list = await app.inject({
      method: "GET",
      url: `/api/v1/shops/${shopId}/customers`,
      headers: { authorization: `Bearer ${token}` },
    });
    expect(list.json().data.items).toHaveLength(0);
  });

  it("يعزل عملاء المحل عن محلو آخر", async () => {
    const ownerToken = await registerAndLogin(OWNER_EMAIL);
    const shopId = await createShop(ownerToken, "محل خاص");
    const created = await app.inject({
      method: "POST",
      url: `/api/v1/shops/${shopId}/customers`,
      headers: { authorization: `Bearer ${ownerToken}` },
      payload: { displayName: "عميل خاص" },
    });
    const customerId = created.json().data.id;

    const otherToken = await registerAndLogin(OTHER_EMAIL);
    const otherShopId = await createShop(otherToken, "محل آخر");

    // قائمة الآخر لا ترى عميل المحل الأول.
    const otherList = await app.inject({
      method: "GET",
      url: `/api/v1/shops/${otherShopId}/customers`,
      headers: { authorization: `Bearer ${otherToken}` },
    });
    expect(otherList.json().data.items).toHaveLength(0);

    // لا يستطيع الوصول لعميل محل غيره (403 لأن العضوية مفقودة في ذلك المحل).
    const detail = await app.inject({
      method: "GET",
      url: `/api/v1/shops/${shopId}/customers/${customerId}`,
      headers: { authorization: `Bearer ${otherToken}` },
    });
    expect(detail.statusCode).toBe(403);

    // ولا تعديله.
    const patch = await app.inject({
      method: "PATCH",
      url: `/api/v1/shops/${shopId}/customers/${customerId}`,
      headers: { authorization: `Bearer ${otherToken}` },
      payload: { displayName: "محاولة" },
    });
    expect(patch.statusCode).toBe(403);
  });

  it("ينشئ رمز دعوة لعميل مرتبط بالمحل", async () => {
    const token = await registerAndLogin(OWNER_EMAIL);
    const shopId = await createShop(token, "محل الدعوة");
    const created = await app.inject({
      method: "POST",
      url: `/api/v1/shops/${shopId}/customers`,
      headers: { authorization: `Bearer ${token}` },
      payload: { displayName: "مدعو" },
    });
    const customerId = created.json().data.id;

    const invite = await app.inject({
      method: "POST",
      url: `/api/v1/shops/${shopId}/customers/${customerId}/invitations`,
      headers: { authorization: `Bearer ${token}` },
    });
    expect(invite.statusCode).toBe(201);
    const data = invite.json().data;
    expect(data.code).toMatch(/^[A-Z2-9]{8}$/);
    expect(data.status).toBe("pending");
    expect(new Date(data.expiresAt).getTime()).toBeGreaterThan(Date.now());
  });

  it("يقبل DELETE بترويسة JSON وبلا جسم (حالة تطبيق المالك)", async () => {
    const token = await registerAndLogin(OWNER_EMAIL);
    const shopId = await createShop(token, "محل الحذف");
    const created = await app.inject({
      method: "POST",
      url: `/api/v1/shops/${shopId}/customers`,
      headers: { authorization: `Bearer ${token}` },
      payload: { displayName: "للحذف" },
    });
    const customerId = created.json().data.id;

    const del = await app.inject({
      method: "DELETE",
      url: `/api/v1/shops/${shopId}/customers/${customerId}`,
      headers: {
        authorization: `Bearer ${token}`,
        "content-type": "application/json",
      },
    });
    expect(del.statusCode).toBe(204);
  });
});

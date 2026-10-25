// اختبارات تكامل وحدة المحلات — على قاعدة wizano_test الحقيقية.
// تغطي: إنشاء محل (201) + ربط المالك + العدّادات، قائمة محلات المستخدم،
// عزل المحلات (عضو لا يرى/يصل محل غيره)، ومنع غير المالك من التعديل.

import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { eq, inArray } from "drizzle-orm";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { migrate } from "drizzle-orm/postgres-js/migrator";
import { buildApp } from "../../app.js";
import { createDb, type Database, type SqlClient } from "../../db/index.js";
import {
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

const OWNER_EMAIL = "shops-test+owner@example.com";
const OTHER_EMAIL = "shops-test+other@example.com";
const PASSWORD = "ShopTest12345";

let app: Awaited<ReturnType<typeof buildApp>>;
let db: Database;
let client: SqlClient;

async function cleanupUsers(): Promise<void> {
  const rows = await db
    .select({ id: users.id })
    .from(users)
    .where(inArray(users.email, [OWNER_EMAIL, OTHER_EMAIL]));
  const ids = rows.map((r) => r.id);
  if (ids.length === 0) return;

  const memberships = await db
    .select({ shopId: shopMembers.shopId })
    .from(shopMembers)
    .where(inArray(shopMembers.userId, ids));
  const shopIds = [...new Set(memberships.map((m) => m.shopId))];

  if (shopIds.length > 0) {
    await db.delete(shopCounters).where(inArray(shopCounters.shopId, shopIds));
    await db.delete(shopMembers).where(inArray(shopMembers.shopId, shopIds));
    await db.delete(shops).where(inArray(shops.id, shopIds));
  }
  await db.delete(refreshTokens).where(inArray(refreshTokens.userId, ids));
  await db.delete(users).where(inArray(users.id, ids));
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

beforeAll(async () => {
  ({ db, client } = createDb());
  await migrate(db, { migrationsFolder });
  await cleanupUsers();
  app = await buildApp({ authDeps: { db }, shopsDeps: { db } });
}, 60000);

afterAll(async () => {
  if (db) await cleanupUsers();
  if (app) await app.close();
  if (client) await client.end({ timeout: 5 });
});

describe("وحدة المحلات", () => {
  it("يرفض الوصول بدون رمز مصادقة", async () => {
    const res = await app.inject({ method: "GET", url: "/api/v1/shops" });
    expect(res.statusCode).toBe(401);
  });

  it("ينشئ محلًا ويربط المنشئ كمالك مع تهيئة العدّادات", async () => {
    const token = await registerAndLogin(OWNER_EMAIL);
    const res = await app.inject({
      method: "POST",
      url: "/api/v1/shops",
      headers: { authorization: `Bearer ${token}` },
      payload: { name: "بقالة الوادي", openingDate: "2026-01-01" },
    });
    expect(res.statusCode).toBe(201);
    const shop = res.json().data;
    expect(shop.name).toBe("بقالة الوادي");
    expect(shop.currency).toBe("YER"); // الافتراضي
    expect(shop.timezone).toBe("Asia/Aden"); // الافتراضي
    expect(shop.openingDate).toBe("2026-01-01");

    const members = await db
      .select()
      .from(shopMembers)
      .where(eq(shopMembers.shopId, shop.id));
    expect(members).toHaveLength(1);
    expect(members[0]?.role).toBe("owner");
    expect(members[0]?.userId).toBeTruthy();

    const counters = await db
      .select()
      .from(shopCounters)
      .where(eq(shopCounters.shopId, shop.id));
    expect(counters).toHaveLength(4);
  });

  it("يرفض اسم محل قصيرًا بخطأ عربي", async () => {
    const token = await registerAndLogin(OWNER_EMAIL);
    const res = await app.inject({
      method: "POST",
      url: "/api/v1/shops",
      headers: { authorization: `Bearer ${token}` },
      payload: { name: "ب" },
    });
    expect(res.statusCode).toBe(400);
    expect(res.json().error.message_ar).toBe("بيانات الطلب غير صالحة.");
  });

  it("يرفض منطقة زمنية غير صالحة", async () => {
    const token = await registerAndLogin(OWNER_EMAIL);
    const res = await app.inject({
      method: "POST",
      url: "/api/v1/shops",
      headers: { authorization: `Bearer ${token}` },
      payload: { name: "محل", timezone: "Not/AZone" },
    });
    expect(res.statusCode).toBe(400);
  });

  it("يعيد محلات المستخدم مع دوره فيها", async () => {
    const token = await registerAndLogin(OWNER_EMAIL);
    const res = await app.inject({
      method: "GET",
      url: "/api/v1/shops",
      headers: { authorization: `Bearer ${token}` },
    });
    expect(res.statusCode).toBe(200);
    expect(res.json().data.items.length).toBeGreaterThanOrEqual(1);
    expect(res.json().data.items[0].role).toBe("owner");
  });

  it("يتيح المالك تعديل محله", async () => {
    const token = await registerAndLogin(OWNER_EMAIL);
    const created = await app.inject({
      method: "POST",
      url: "/api/v1/shops",
      headers: { authorization: `Bearer ${token}` },
      payload: { name: "اسم قديم" },
    });
    const shopId = created.json().data.id;

    const updated = await app.inject({
      method: "PATCH",
      url: `/api/v1/shops/${shopId}`,
      headers: { authorization: `Bearer ${token}` },
      payload: { name: "اسم جديد", currency: "USD" },
    });
    expect(updated.statusCode).toBe(200);
    expect(updated.json().data.name).toBe("اسم جديد");
    expect(updated.json().data.currency).toBe("USD");
  });

  it("يعزل محل مستخدم عن آخر: لا وصول ولا ظهور", async () => {
    const ownerToken = await registerAndLogin(OWNER_EMAIL);
    const created = await app.inject({
      method: "POST",
      url: "/api/v1/shops",
      headers: { authorization: `Bearer ${ownerToken}` },
      payload: { name: "محل خاص" },
    });
    const shopId = created.json().data.id;

    const otherToken = await registerAndLogin(OTHER_EMAIL);

    // لا يظهر في قائمة الآخر.
    const list = await app.inject({
      method: "GET",
      url: "/api/v1/shops",
      headers: { authorization: `Bearer ${otherToken}` },
    });
    expect(list.json().data.items).toHaveLength(0);

    // لا يستطيع الوصول لتفاصيله.
    const detail = await app.inject({
      method: "GET",
      url: `/api/v1/shops/${shopId}`,
      headers: { authorization: `Bearer ${otherToken}` },
    });
    expect(detail.statusCode).toBe(403);

    // ولا تعديله.
    const patch = await app.inject({
      method: "PATCH",
      url: `/api/v1/shops/${shopId}`,
      headers: { authorization: `Bearer ${otherToken}` },
      payload: { name: "محاولة اختراق" },
    });
    expect(patch.statusCode).toBe(403);
  });

  it("يمنع الموظف (غير المالك) من تعديل المحل", async () => {
    const ownerToken = await registerAndLogin(OWNER_EMAIL);
    const created = await app.inject({
      method: "POST",
      url: "/api/v1/shops",
      headers: { authorization: `Bearer ${ownerToken}` },
      payload: { name: "محل بموظف" },
    });
    const shopId = created.json().data.id;

    // نضيف المستخدم الآخر كموظف في هذا المحل مباشرة.
    const otherRows = await db
      .select({ id: users.id })
      .from(users)
      .where(eq(users.email, OTHER_EMAIL))
      .limit(1);
    const otherId = otherRows[0]?.id;
    if (!otherId) throw new Error("لم يُعثر على المستخدم الآخر");
    await db.insert(shopMembers).values({
      shopId,
      userId: otherId,
      role: "staff",
      permissionKeys: ["purchases.create"],
    });

    const otherToken = await registerAndLogin(OTHER_EMAIL);
    const patch = await app.inject({
      method: "PATCH",
      url: `/api/v1/shops/${shopId}`,
      headers: { authorization: `Bearer ${otherToken}` },
      payload: { name: "تعديل موظف" },
    });
    expect(patch.statusCode).toBe(403);
    expect(patch.json().error.message_ar).toContain("للمالك فقط");

    // لكنه يرى تفاصيل المحل (عضو فعّال).
    const detail = await app.inject({
      method: "GET",
      url: `/api/v1/shops/${shopId}`,
      headers: { authorization: `Bearer ${otherToken}` },
    });
    expect(detail.statusCode).toBe(200);
  });
});

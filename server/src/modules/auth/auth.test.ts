// اختبارات تكامل المصادقة — على قاعدة wizano_test الحقيقية.
// تغطي: التسجيل، الدخول، رفض كلمة المرور الخاطئة، رمز الوصول، /me،
// تدوير رمز التجديد، كشف إعادة الاستخدام (إبطال السلسلة)، والخروج.

import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { eq, inArray, like } from "drizzle-orm";
import { buildApp } from "../../app.js";
import { createDb, type Database, type SqlClient } from "../../db/index.js";
import { migrate } from "drizzle-orm/postgres-js/migrator";
import { refreshTokens, users } from "../../db/schema.js";
import path from "node:path";
import { fileURLToPath } from "node:url";

const migrationsFolder = path.join(
  path.dirname(fileURLToPath(import.meta.url)),
  "../../db/migrations",
);

const PREFIX = "auth-test+";
const EMAIL = `${PREFIX}user@example.com`;
const PASSWORD = "SuperSecret123";

let app: Awaited<ReturnType<typeof buildApp>>;
let db: Database;
let client: SqlClient;

async function cleanup(): Promise<void> {
  const rows = await db
    .select({ id: users.id })
    .from(users)
    .where(like(users.email, `${PREFIX}%`));
  const ids = rows.map((r) => r.id);
  if (ids.length > 0) {
    await db.delete(refreshTokens).where(inArray(refreshTokens.userId, ids));
    await db.delete(users).where(inArray(users.id, ids));
  }
}

beforeAll(async () => {
  ({ db, client } = createDb());
  await migrate(db, { migrationsFolder });
  await cleanup();
  app = await buildApp({ authDeps: { db } });
}, 60000);

afterAll(async () => {
  if (db) await cleanup();
  if (app) await app.close();
  if (client) await client.end({ timeout: 5 });
});

describe("مصادقة المستخدمين", () => {
  it("يسجّل مستخدمًا جديدًا ويعيد رمزَي الوصول والتجديد", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/api/v1/auth/register",
      payload: { displayName: "مستخدم اختبار", email: EMAIL, password: PASSWORD },
    });
    expect(res.statusCode).toBe(201);
    const body = res.json();
    expect(body.data.user.email).toBe(EMAIL);
    expect(body.data.user.passwordHash).toBeUndefined();
    expect(typeof body.data.tokens.accessToken).toBe("string");
    expect(typeof body.data.tokens.refreshToken).toBe("string");
  });

  it("يرفض تسجيل بريد مكرر", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/api/v1/auth/register",
      payload: { displayName: "مكرر", email: EMAIL, password: PASSWORD },
    });
    expect(res.statusCode).toBe(409);
    expect(res.json().error.code).toBe("CONFLICT");
  });

  it("يرفض بيانات تسجيل ناقصة بخطأ تحقق عربي", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/api/v1/auth/register",
      payload: { displayName: "بلا كلمة مرور" },
    });
    expect(res.statusCode).toBe(400);
    expect(res.json().error.message_ar).toBe("بيانات الطلب غير صالحة.");
  });

  it("يسجّل الدخول بنجاح", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/api/v1/auth/login",
      payload: { email: EMAIL, password: PASSWORD },
    });
    expect(res.statusCode).toBe(200);
    expect(res.json().data.tokens.accessToken).toBeTruthy();
  });

  it("يرفض كلمة مرور خاطئة برسالة موحّدة", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/api/v1/auth/login",
      payload: { email: EMAIL, password: "wrong-password" },
    });
    expect(res.statusCode).toBe(401);
    expect(res.json().error.message_ar).toContain("غير صحيحة");
  });

  it("يرفض بريدًا غير مسجّل بنفس الرسالة الموحّدة", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/api/v1/auth/login",
      payload: { email: `${PREFIX}nobody@example.com`, password: PASSWORD },
    });
    expect(res.statusCode).toBe(401);
    expect(res.json().error.message_ar).toContain("غير صحيحة");
  });

  it("يسمح بالوصول إلى /me برمز صالح ويرفضه بدون ترويسة", async () => {
    const login = await app.inject({
      method: "POST",
      url: "/api/v1/auth/login",
      payload: { email: EMAIL, password: PASSWORD },
    });
    const accessToken = login.json().data.tokens.accessToken;

    const ok = await app.inject({
      method: "GET",
      url: "/api/v1/me",
      headers: { authorization: `Bearer ${accessToken}` },
    });
    expect(ok.statusCode).toBe(200);
    expect(ok.json().data.user.email).toBe(EMAIL);

    const bad = await app.inject({ method: "GET", url: "/api/v1/me" });
    expect(bad.statusCode).toBe(401);

    const invalid = await app.inject({
      method: "GET",
      url: "/api/v1/me",
      headers: { authorization: "Bearer not-a-real-token" },
    });
    expect(invalid.statusCode).toBe(401);
  });

  it("يدوّر رمز التجديد: الرمز القديم يُبطَل والجديد يعمل", async () => {
    const login = await app.inject({
      method: "POST",
      url: "/api/v1/auth/login",
      payload: { email: EMAIL, password: PASSWORD },
    });
    const firstRefresh = login.json().data.tokens.refreshToken;

    const rotated = await app.inject({
      method: "POST",
      url: "/api/v1/auth/refresh",
      payload: { refreshToken: firstRefresh },
    });
    expect(rotated.statusCode).toBe(200);
    const secondRefresh = rotated.json().data.tokens.refreshToken;
    expect(secondRefresh).not.toBe(firstRefresh);

    // الرمز القديم مُبطَل الآن.
    const reuse = await app.inject({
      method: "POST",
      url: "/api/v1/auth/refresh",
      payload: { refreshToken: firstRefresh },
    });
    expect(reuse.statusCode).toBe(401);
  });

  it("يبطل السلسلة كاملة عند إعادة استخدام رمز مُبطَل (كشف السرقة)", async () => {
    const login = await app.inject({
      method: "POST",
      url: "/api/v1/auth/login",
      payload: { email: EMAIL, password: PASSWORD },
    });
    const oldRefresh = login.json().data.tokens.refreshToken;

    const rotated = await app.inject({
      method: "POST",
      url: "/api/v1/auth/refresh",
      payload: { refreshToken: oldRefresh },
    });
    const newRefresh = rotated.json().data.tokens.refreshToken;

    // إعادة استخدام القديم تُبطِل السلسلة.
    await app.inject({
      method: "POST",
      url: "/api/v1/auth/refresh",
      payload: { refreshToken: oldRefresh },
    });

    // الجديد (في نفس السلسلة) أصبح مُبطَلًا أيضًا.
    const afterBreach = await app.inject({
      method: "POST",
      url: "/api/v1/auth/refresh",
      payload: { refreshToken: newRefresh },
    });
    expect(afterBreach.statusCode).toBe(401);
  });

  it("يخرج ويُبطِل رمز التجديد فلا يصلح بعده", async () => {
    const login = await app.inject({
      method: "POST",
      url: "/api/v1/auth/login",
      payload: { email: EMAIL, password: PASSWORD },
    });
    const refreshToken = login.json().data.tokens.refreshToken;

    const logout = await app.inject({
      method: "POST",
      url: "/api/v1/auth/logout",
      payload: { refreshToken },
    });
    expect(logout.statusCode).toBe(204);

    const afterLogout = await app.inject({
      method: "POST",
      url: "/api/v1/auth/refresh",
      payload: { refreshToken },
    });
    expect(afterLogout.statusCode).toBe(401);
  });

  it("لا يخزّن كلمة المرور خامًا في القاعدة", async () => {
    const rows = await db
      .select({ passwordHash: users.passwordHash })
      .from(users)
      .where(eq(users.email, EMAIL))
      .limit(1);
    expect(rows[0]?.passwordHash).toBeTruthy();
    expect(rows[0]?.passwordHash).not.toBe(PASSWORD);
    expect(rows[0]?.passwordHash?.startsWith("$argon2id$")).toBe(true);
  });
});

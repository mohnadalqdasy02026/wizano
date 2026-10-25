// منطق المصادقة — تسجيل، دخول، تدوير رمز التجديد، خروج، وجلب المستخدم الحالي.
// لا أسرار في السجلات؛ لا كشف كلمة المرور.

import { and, eq, isNull } from "drizzle-orm";
import type { Database } from "../../db/index.js";
import { refreshTokens as refreshTokensTable, shops, shopMembers, users } from "../../db/schema.js";
import { conflict, notFound, unauthorized } from "../../common/errors.js";
import { hashPassword, verifyPassword } from "./password.js";
import {
  generateRefreshToken,
  hashRefreshToken,
  newAccessJti,
  newFamilyId,
  refreshExpiryDate,
  signAccessToken,
} from "./tokens.js";

export interface AuthTokens {
  accessToken: string;
  refreshToken: string;
  tokenType: "Bearer";
  expiresIn: number;
}

export interface PublicUser {
  id: string;
  displayName: string;
  email: string | null;
  phone: string | null;
  status: string;
  createdAt: string;
}

export interface AuthResult {
  user: PublicUser;
  tokens: AuthTokens;
}

function toPublicUser(row: {
  id: string;
  displayName: string;
  email: string | null;
  phone: string | null;
  status: string;
  createdAt: Date;
}): PublicUser {
  return {
    id: row.id,
    displayName: row.displayName,
    email: row.email,
    phone: row.phone,
    status: row.status,
    createdAt: row.createdAt.toISOString(),
  };
}

// رمز الوصول يحمل الدور الأساسي للمستخدم (owner إن وُجد وإلا أول دور مرتَّبًا).
async function primaryRole(db: Database, userId: string): Promise<string> {
  const rows = await db
    .select({ role: shopMembers.role })
    .from(shopMembers)
    .where(
      and(eq(shopMembers.userId, userId), eq(shopMembers.status, "active")),
    );
  if (rows.length === 0) return "owner"; // مستخدم جديد بلا محل بعد
  const order = ["system_admin", "owner", "staff", "customer"];
  rows.sort((a, b) => order.indexOf(a.role) - order.indexOf(b.role));
  return rows[0]?.role ?? "owner";
}

async function issueTokens(db: Database, userId: string): Promise<AuthTokens> {
  const role = await primaryRole(db, userId);
  const { token: accessToken, expiresIn } = await signAccessToken({
    sub: userId,
    role,
    jti: newAccessJti(),
  });

  const { raw, hash } = generateRefreshToken();
  await db.insert(refreshTokensTable).values({
    userId,
    tokenHash: hash,
    familyId: newFamilyId(),
    expiresAt: refreshExpiryDate(),
  });

  return { accessToken, refreshToken: raw, tokenType: "Bearer", expiresIn };
}

export async function registerUser(
  db: Database,
  input: {
    displayName: string;
    email?: string;
    phone?: string;
    password: string;
  },
): Promise<AuthResult> {
  const email = input.email ?? null;
  const phone = input.phone ?? null;

  // تحقق مسبق من التكرار (الفهارس الفريدة الجزئية تمنع السباق أيضًا).
  if (email) {
    const existing = await db
      .select({ id: users.id })
      .from(users)
      .where(eq(users.email, email))
      .limit(1);
    if (existing.length > 0) {
      throw conflict("البريد الإلكتروني مستخدم بالفعل.");
    }
  }
  if (phone) {
    const existing = await db
      .select({ id: users.id })
      .from(users)
      .where(eq(users.phone, phone))
      .limit(1);
    if (existing.length > 0) {
      throw conflict("رقم الهاتف مستخدم بالفعل.");
    }
  }

  const passwordHash = await hashPassword(input.password);

  const inserted = await db
    .insert(users)
    .values({
      displayName: input.displayName,
      email,
      phone,
      passwordHash,
    })
    .returning();

  const user = inserted[0];
  if (!user) throw new Error("فشل إنشاء المستخدم");

  const tokens = await issueTokens(db, user.id);
  return { user: toPublicUser(user), tokens };
}

export async function loginUser(
  db: Database,
  input: { email?: string; phone?: string; password: string },
): Promise<AuthResult> {
  const identifier = input.email
    ? eq(users.email, input.email)
    : eq(users.phone, input.phone as string);

  const rows = await db.select().from(users).where(identifier).limit(1);
  const user = rows[0];

  // رسالة موحّدة لمنع تخمين وجود الحساب (لا نفرّق بين "غير موجود" و"كلمة مرور خاطئة").
  if (!user) {
    throw unauthorized("البريد/الهاتف أو كلمة المرور غير صحيحة.");
  }
  if (user.status !== "active") {
    throw unauthorized("الحساب غير مُفعّل.");
  }

  const ok = await verifyPassword(input.password, user.passwordHash);
  if (!ok) {
    throw unauthorized("البريد/الهاتف أو كلمة المرور غير صحيحة.");
  }

  await db
    .update(users)
    .set({ lastLoginAt: new Date() })
    .where(eq(users.id, user.id));

  const tokens = await issueTokens(db, user.id);
  return { user: toPublicUser(user), tokens };
}

// تدوير رمز التجديد: يُبطَل المستخدم ويُصدر جديد في نفس السلسلة.
// إعادة استخدام رمز مُبطَل = اشتباه سرقة → إبطال السلسلة كاملة (R-08).
export async function refreshTokens(
  db: Database,
  rawRefreshToken: string,
): Promise<AuthResult> {
  const tokenHash = hashRefreshToken(rawRefreshToken);

  const rows = await db
    .select()
    .from(refreshTokensTable)
    .where(eq(refreshTokensTable.tokenHash, tokenHash))
    .limit(1);
  const stored = rows[0];

  if (!stored) {
    throw unauthorized("رمز التجديد غير صالح.");
  }

  if (stored.revokedAt) {
    // إعادة استخدام رمز مُبطَل → إبطال كل السلسلة.
    await db
      .update(refreshTokensTable)
      .set({ revokedAt: new Date() })
      .where(
        and(
          eq(refreshTokensTable.familyId, stored.familyId),
          isNull(refreshTokensTable.revokedAt),
        ),
      );
    throw unauthorized("رمز التجديد أُبطل. الرجاء تسجيل الدخول مجددًا.");
  }

  if (stored.expiresAt.getTime() < Date.now()) {
    throw unauthorized("انتهت صلاحية رمز التجديد.");
  }

  const userRows = await db
    .select()
    .from(users)
    .where(eq(users.id, stored.userId))
    .limit(1);
  const user = userRows[0];
  if (!user || user.status !== "active") {
    throw unauthorized("الحساب غير متاح.");
  }

  // إبطال الحالي + إصدار جديد في نفس السلسلة.
  const { raw, hash } = generateRefreshToken();
  const inserted = await db
    .insert(refreshTokensTable)
    .values({
      userId: user.id,
      deviceId: stored.deviceId,
      tokenHash: hash,
      familyId: stored.familyId,
      expiresAt: refreshExpiryDate(),
    })
    .returning({ id: refreshTokensTable.id });
  const newId = inserted[0]?.id;

  await db
    .update(refreshTokensTable)
    .set({ revokedAt: new Date(), replacedByTokenId: newId ?? null })
    .where(eq(refreshTokensTable.id, stored.id));

  const role = await primaryRole(db, user.id);
  const { token: accessToken, expiresIn } = await signAccessToken({
    sub: user.id,
    role,
    jti: newAccessJti(),
  });

  return {
    user: toPublicUser(user),
    tokens: { accessToken, refreshToken: raw, tokenType: "Bearer", expiresIn },
  };
}

export async function logoutUser(
  db: Database,
  rawRefreshToken: string,
): Promise<void> {
  const tokenHash = hashRefreshToken(rawRefreshToken);
  const result = await db
    .update(refreshTokensTable)
    .set({ revokedAt: new Date() })
    .where(
      and(eq(refreshTokensTable.tokenHash, tokenHash), isNull(refreshTokensTable.revokedAt)),
    )
    .returning({ id: refreshTokensTable.id });
  if (result.length === 0) {
    throw notFound("رمز تجديد فعّال غير موجود.");
  }
}

export interface CurrentUser {
  user: PublicUser;
  memberships: Array<{
    shopId: string;
    shopName: string;
    role: string;
    permissionKeys: string[];
  }>;
}

export async function getCurrentUser(
  db: Database,
  userId: string,
): Promise<CurrentUser> {
  const userRows = await db
    .select()
    .from(users)
    .where(eq(users.id, userId))
    .limit(1);
  const user = userRows[0];
  if (!user) throw notFound("المستخدم غير موجود.");

  const membershipRows = await db
    .select({
      shopId: shopMembers.shopId,
      shopName: shops.name,
      role: shopMembers.role,
      permissionKeys: shopMembers.permissionKeys,
      status: shopMembers.status,
    })
    .from(shopMembers)
    .innerJoin(shops, eq(shops.id, shopMembers.shopId))
    .where(
      and(eq(shopMembers.userId, userId), eq(shopMembers.status, "active")),
    );

  return {
    user: toPublicUser(user),
    memberships: membershipRows.map((m) => ({
      shopId: m.shopId,
      shopName: m.shopName,
      role: m.role,
      permissionKeys: m.permissionKeys,
    })),
  };
}

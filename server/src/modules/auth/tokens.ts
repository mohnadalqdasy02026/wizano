// رموز الوصول والتجديد — JWT للوصول (jose) + رمز تجديد عشوائي ببصمة SHA-256 (D-05).
// رمز التجديد لا يُخزَّن خامًا؛ يُخزَّن SHA-256 فقط. التدوير يُبطل القديم.

import { createHash, randomBytes, randomUUID } from "node:crypto";
import { SignJWT, jwtVerify } from "jose";
import { env } from "../../config/index.js";

const accessSecret = new TextEncoder().encode(env.JWT_ACCESS_SECRET);

export interface AccessTokenClaims {
  sub: string; // معرّف المستخدم
  role: string; // role الأساسي
  jti: string;
}

export async function signAccessToken(
  claims: AccessTokenClaims,
): Promise<{ token: string; expiresIn: number }> {
  const token = await new SignJWT({ role: claims.role })
    .setProtectedHeader({ alg: "HS256" })
    .setSubject(claims.sub)
    .setJti(claims.jti)
    .setIssuedAt()
    .setIssuer("wizano-server")
    .setAudience("wizano-app")
    .setExpirationTime(`${env.ACCESS_TOKEN_TTL_SECONDS}s`)
    .sign(accessSecret);
  return { token, expiresIn: env.ACCESS_TOKEN_TTL_SECONDS };
}

export async function verifyAccessToken(
  token: string,
): Promise<AccessTokenClaims> {
  const { payload } = await jwtVerify(token, accessSecret, {
    issuer: "wizano-server",
    audience: "wizano-app",
  });
  if (!payload.sub || typeof payload.role !== "string" || !payload.jti) {
    throw new Error("رمز الوصول غير مكتمل");
  }
  return { sub: payload.sub, role: payload.role, jti: payload.jti };
}

// ---------------------------------------------------------------------------
// رمز التجديد: سلسلة عشوائية 256-bit؛ يُخزَّن hash فقط.
// ---------------------------------------------------------------------------

export function generateRefreshToken(): { raw: string; hash: string } {
  const raw = randomBytes(32).toString("base64url");
  return { raw, hash: hashRefreshToken(raw) };
}

export function hashRefreshToken(raw: string): string {
  return createHash("sha256").update(raw).digest("hex");
}

export function newFamilyId(): string {
  return randomUUID();
}

export function refreshExpiryDate(): Date {
  return new Date(Date.now() + env.REFRESH_TOKEN_TTL_DAYS * 24 * 60 * 60 * 1000);
}

export function newAccessJti(): string {
  return randomUUID();
}

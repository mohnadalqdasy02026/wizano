// وسيط المصادقة والصلاحيات (docs/04-architecture.md §6).
// كل مسار حساس: مصادقة → تحقق الدور → تحقق الصلاحية → تحقق الانتماء للمحل.
// `shop_id` يُستخرج من انتماء المستخدم المؤكَّد، لا من الطلب.

import type { FastifyReply, FastifyRequest } from "fastify";
import { and, eq } from "drizzle-orm";
import { db } from "../db/index.js";
import { shopMembers } from "../db/schema.js";
import { forbidden, unauthorized } from "../common/errors.js";
import { verifyAccessToken } from "../modules/auth/tokens.js";

export interface AuthContext {
  userId: string;
  role: string;
  jti: string;
}

declare module "fastify" {
  interface FastifyRequest {
    auth?: AuthContext;
  }
}

export async function authenticate(
  req: FastifyRequest,
  _reply: FastifyReply,
): Promise<void> {
  const header = req.headers.authorization;
  if (!header || !header.startsWith("Bearer ")) {
    throw unauthorized("ترويسة المصادقة مفقودة أو غير صحيحة.");
  }
  const token = header.slice("Bearer ".length).trim();
  if (!token) throw unauthorized("رمز الوصول مفقود.");

  try {
    const claims = await verifyAccessToken(token);
    req.auth = { userId: claims.sub, role: claims.role, jti: claims.jti };
  } catch {
    // لا نكشف تفاصيل التحقق (منتهي/توقيع مغلوط) لمنع التخمين.
    throw unauthorized("رمز الوصول غير صالح أو منتهي الصلاحية.");
  }
}

export interface Membership {
  shopId: string;
  role: string;
  permissionKeys: string[];
}

// يتحقق أن المستخدم عضو فعّال في المحل المطلوب، ويعيد عضويته.
export async function requireShopMembership(
  userId: string,
  shopId: string,
): Promise<Membership> {
  const rows = await db
    .select({
      shopId: shopMembers.shopId,
      role: shopMembers.role,
      permissionKeys: shopMembers.permissionKeys,
    })
    .from(shopMembers)
    .where(
      and(
        eq(shopMembers.userId, userId),
        eq(shopMembers.shopId, shopId),
        eq(shopMembers.status, "active"),
      ),
    )
    .limit(1);

  const membership = rows[0];
  if (!membership) {
    // رسالة موحّدة كي لا نكشف وجود المحل من عدمه (R-06).
    throw forbidden("لا تملك صلاحية الوصول إلى هذا المحل.");
  }
  return membership;
}

// صلاحية工作人员的 مفاتيح (owner يملك الكل).
export function hasPermission(
  membership: Pick<Membership, "role" | "permissionKeys">,
  required: string,
): boolean {
  if (membership.role === "owner") return true;
  if (membership.role !== "staff") return false;
  return membership.permissionKeys.includes(required);
}

export function requirePermission(
  membership: Pick<Membership, "role" | "permissionKeys">,
  required: string,
): void {
  if (!hasPermission(membership, required)) {
    throw forbidden("لا تملك صلاحية تنفيذ هذه العملية.");
  }
}

export function requireOperationalRole(
  membership: Pick<Membership, "role">,
): void {
  if (membership.role !== "owner" && membership.role !== "staff") {
    throw forbidden("هذا الإجراء متاح لصاحب المحل أو الموظف فقط.");
  }
}

export function requireOwner(
  membership: Pick<Membership, "role">,
): void {
  if (membership.role !== "owner") {
    throw forbidden("هذا الإجراء متاح لمالك المحل فقط.");
  }
}

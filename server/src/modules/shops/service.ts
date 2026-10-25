// منطق وحدة المحلات — إنشاء محل (مع ربط المالك)، جلب، وتعديل.
// كل استعلام إداري مُقيَّد بانتماء المستخدم المؤكَّد (R-06).

import { and, eq } from "drizzle-orm";
import type { Database } from "../../db/index.js";
import { shops, shopMembers, shopCounters } from "../../db/schema.js";
import { notFound } from "../../common/errors.js";

export interface ShopView {
  id: string;
  name: string;
  currency: string;
  timezone: string;
  openingDate: string | null;
  status: string;
  createdAt: string;
  updatedAt: string;
}

function toShopView(row: {
  id: string;
  name: string;
  currency: string;
  timezone: string;
  openingDate: string | null;
  status: string;
  createdAt: Date;
  updatedAt: Date;
}): ShopView {
  return {
    id: row.id,
    name: row.name,
    currency: row.currency,
    timezone: row.timezone,
    openingDate: row.openingDate,
    status: row.status,
    createdAt: row.createdAt.toISOString(),
    updatedAt: row.updatedAt.toISOString(),
  };
}

// أنماط العدّادات المُنشأة لكل محل جديد (أرقام العمليات ضمن نطاق المحل).
const COUNTER_KINDS = ["purchase", "payment", "return", "adjustment"] as const;

// إنشاء محل + ربط المُنشئ كـ owner + تهيئة العدّادات — كلها ضمن معاملة واحدة.
export async function createShop(
  db: Database,
  ownerUserId: string,
  input: {
    name: string;
    currency: string;
    timezone: string;
    openingDate?: string;
  },
): Promise<ShopView> {
  return db.transaction(async (tx) => {
    const insertedShops = await tx
      .insert(shops)
      .values({
        name: input.name,
        currency: input.currency,
        timezone: input.timezone,
        openingDate: input.openingDate ?? null,
        createdBy: ownerUserId,
      })
      .returning();
    const shop = insertedShops[0];
    if (!shop) throw new Error("فشل إنشاء المحل");

    await tx.insert(shopMembers).values({
      shopId: shop.id,
      userId: ownerUserId,
      role: "owner",
      permissionKeys: [],
    });

    await tx.insert(shopCounters).values(
      COUNTER_KINDS.map((kind) => ({ shopId: shop.id, kind })),
    );

    return toShopView(shop);
  });
}

// محلات المستخدم التي هو عضو فعّال فيها.
export async function listUserShops(
  db: Database,
  userId: string,
): Promise<Array<ShopView & { role: string; permissionKeys: string[] }>> {
  const rows = await db
    .select({
      id: shops.id,
      name: shops.name,
      currency: shops.currency,
      timezone: shops.timezone,
      openingDate: shops.openingDate,
      status: shops.status,
      createdAt: shops.createdAt,
      updatedAt: shops.updatedAt,
      role: shopMembers.role,
      permissionKeys: shopMembers.permissionKeys,
    })
    .from(shopMembers)
    .innerJoin(shops, eq(shops.id, shopMembers.shopId))
    .where(
      and(eq(shopMembers.userId, userId), eq(shopMembers.status, "active")),
    );

  return rows.map((r) => ({
    ...toShopView(r),
    role: r.role,
    permissionKeys: r.permissionKeys,
  }));
}

// تفاصيل محل — يفترض أن الوسيط تحقق من الانتماء مسبقًا.
export async function getShopById(
  db: Database,
  shopId: string,
): Promise<ShopView> {
  const rows = await db
    .select()
    .from(shops)
    .where(eq(shops.id, shopId))
    .limit(1);
  const shop = rows[0];
  if (!shop) throw notFound("المحل غير موجود.");
  return toShopView(shop);
}

// تعديل محل — يفترض أن الوسيط تحقق أن المستخدم owner.
export async function updateShop(
  db: Database,
  shopId: string,
  patch: {
    name?: string;
    currency?: string;
    timezone?: string;
    openingDate?: string | null;
  },
): Promise<ShopView> {
  const updated = await db
    .update(shops)
    .set({
      ...(patch.name !== undefined ? { name: patch.name } : {}),
      ...(patch.currency !== undefined ? { currency: patch.currency } : {}),
      ...(patch.timezone !== undefined ? { timezone: patch.timezone } : {}),
      ...(patch.openingDate !== undefined
        ? { openingDate: patch.openingDate }
        : {}),
    })
    .where(eq(shops.id, shopId))
    .returning();
  const shop = updated[0];
  if (!shop) throw notFound("المحل غير موجود.");
  return toShopView(shop);
}

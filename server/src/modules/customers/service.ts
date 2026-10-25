// منطق وحدة العملاء — إنشاء/جلب/تعديل مع ربط العميل بالمحل.
// كل وصول مُقيَّد بانتماء المحل المؤكَّد (R-06): العميل يُقرأ/يُعدَّل فقط إن كان
// مرتبطًا بالمحل عبر customer_shop_links بحالة active.

import { and, eq, gt, ilike, or, sql } from "drizzle-orm";
import { randomUUID } from "node:crypto";
import type { Database } from "../../db/index.js";
import {
  customers,
  customerShopLinks,
  customerUserLinks,
  invitations,
  shopMembers,
} from "../../db/schema.js";
import { conflict, notFound } from "../../common/errors.js";

export interface CustomerView {
  id: string;
  displayName: string;
  phone: string | null;
  notes: string | null;
  archivedAt: string | null;
  createdAt: string;
  updatedAt: string;
}

function toCustomerView(row: {
  id: string;
  displayName: string;
  phone: string | null;
  notes: string | null;
  archivedAt: Date | null;
  createdAt: Date;
  updatedAt: Date;
}): CustomerView {
  return {
    id: row.id,
    displayName: row.displayName,
    phone: row.phone,
    notes: row.notes,
    archivedAt: row.archivedAt ? row.archivedAt.toISOString() : null,
    createdAt: row.createdAt.toISOString(),
    updatedAt: row.updatedAt.toISOString(),
  };
}

// يولّد رمز دعوة قصيرًا فريدًا (8 أحرف كبيرة/أرقام، بلا أحرف ملتبسة).
const CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
function generateCode(length = 8): string {
  let out = "";
  for (let i = 0; i < length; i++) {
    out += CODE_ALPHABET[Math.floor(Math.random() * CODE_ALPHABET.length)];
  }
  return out;
}

// إنشاء عميل وربطه بالمحل — ضمن معاملة واحدة.
export async function createCustomer(
  db: Database,
  shopId: string,
  input: { id?: string; displayName: string; phone?: string; notes?: string },
): Promise<CustomerView> {
  return db.transaction(async (tx) => {
    const inserted = await tx
      .insert(customers)
      .values({
        id: input.id ?? randomUUID(),
        displayName: input.displayName,
        phone: input.phone ?? null,
        notes: input.notes ?? null,
      })
      .returning();
    const customer = inserted[0];
    if (!customer) throw new Error("فشل إنشاء العميل");

    await tx.insert(customerShopLinks).values({
      customerId: customer.id,
      shopId,
    });

    return toCustomerView(customer);
  });
}

// عملاء المحل (اختياريًا ببحث بالاسم أو الهاتف). يستثني المؤرشفين افتراضيًا.
export async function listShopCustomers(
  db: Database,
  shopId: string,
  search?: string,
): Promise<CustomerView[]> {
  const base = and(
    eq(customerShopLinks.shopId, shopId),
    eq(customerShopLinks.status, "active"),
    sql`${customers.archivedAt} is null`,
  );

  const where = search
    ? and(
        base,
        or(
          ilike(customers.displayName, `%${search}%`),
          ilike(customers.phone, `%${search}%`),
        ),
      )
    : base;

  const rows = await db
    .select({
      id: customers.id,
      displayName: customers.displayName,
      phone: customers.phone,
      notes: customers.notes,
      archivedAt: customers.archivedAt,
      createdAt: customers.createdAt,
      updatedAt: customers.updatedAt,
    })
    .from(customerShopLinks)
    .innerJoin(customers, eq(customers.id, customerShopLinks.customerId))
    .where(where)
    .orderBy(customers.displayName);

  return rows.map(toCustomerView);
}

// يتحقق أن العميل مرتبط فعليًا بالمحل؛ وإلا 404 موحّد (لا نكشف وجوده).
async function requireLinkedCustomer(
  db: Database,
  shopId: string,
  customerId: string,
): Promise<void> {
  const rows = await db
    .select({ id: customerShopLinks.id })
    .from(customerShopLinks)
    .where(
      and(
        eq(customerShopLinks.shopId, shopId),
        eq(customerShopLinks.customerId, customerId),
        eq(customerShopLinks.status, "active"),
      ),
    )
    .limit(1);
  if (rows.length === 0) throw notFound("العميل غير موجود.");
}

export async function getCustomerForShop(
  db: Database,
  shopId: string,
  customerId: string,
): Promise<CustomerView> {
  await requireLinkedCustomer(db, shopId, customerId);
  const rows = await db
    .select()
    .from(customers)
    .where(eq(customers.id, customerId))
    .limit(1);
  const customer = rows[0];
  if (!customer) throw notFound("العميل غير موجود.");
  return toCustomerView(customer);
}

export async function updateCustomer(
  db: Database,
  shopId: string,
  customerId: string,
  patch: { displayName?: string; phone?: string | null; notes?: string | null },
): Promise<CustomerView> {
  await requireLinkedCustomer(db, shopId, customerId);
  const updated = await db
    .update(customers)
    .set({
      ...(patch.displayName !== undefined ? { displayName: patch.displayName } : {}),
      ...(patch.phone !== undefined ? { phone: patch.phone } : {}),
      ...(patch.notes !== undefined ? { notes: patch.notes } : {}),
      version: sql`${customers.version} + 1`,
    })
    .where(eq(customers.id, customerId))
    .returning();
  const customer = updated[0];
  if (!customer) throw notFound("العميل غير موجود.");
  return toCustomerView(customer);
}

// أرشفة عميل (حذف منطقي) — يفترض التحقق من الربط.
export async function archiveCustomer(
  db: Database,
  shopId: string,
  customerId: string,
): Promise<void> {
  await requireLinkedCustomer(db, shopId, customerId);
  await db
    .update(customers)
    .set({ archivedAt: new Date() })
    .where(eq(customers.id, customerId));
}

// ---------------------------------------------------------------------------
// S12 — ربط العميل بالمحل عبر رمز دعوة (الجانب الداخلي: إنشاء الرمز).
// ---------------------------------------------------------------------------

export interface InvitationView {
  id: string;
  code: string;
  status: string;
  expiresAt: string;
}

// ينشئ رمز دعوة لعميل مرتبط بالمحل (يُستخدم لاحقًا من تطبيق العميل).
export async function createInvitation(
  db: Database,
  shopId: string,
  customerId: string,
  createdByUserId: string,
  ttlDays = 7,
): Promise<InvitationView> {
  await requireLinkedCustomer(db, shopId, customerId);

  // محاولات محدودة لتوليد رمز غير مكرَّر.
  for (let attempt = 0; attempt < 5; attempt++) {
    const code = generateCode();
    const existing = await db
      .select({ id: invitations.id })
      .from(invitations)
      .where(eq(invitations.code, code))
      .limit(1);
    if (existing.length > 0) continue;

    const expiresAt = new Date(Date.now() + ttlDays * 24 * 60 * 60 * 1000);
    const inserted = await db
      .insert(invitations)
      .values({ shopId, customerId, code, expiresAt, createdBy: createdByUserId })
      .returning();
    const row = inserted[0];
    if (!row) throw new Error("فشل إنشاء رمز الدعوة");
    return {
      id: row.id,
      code: row.code,
      status: row.status,
      expiresAt: row.expiresAt.toISOString(),
    };
  }
  throw conflict("تعذر توليد رمز دعوة فريد. حاول مجددًا.");
}

export async function acceptInvitation(
  db: Database,
  userId: string,
  code: string,
): Promise<{ shopId: string; customerId: string }> {
  return db.transaction(async (tx) => {
    const rows = await tx
      .select()
      .from(invitations)
      .where(and(eq(invitations.code, code), eq(invitations.status, "pending"), gt(invitations.expiresAt, new Date())))
      .limit(1);
    const invitation = rows[0];
    if (!invitation) throw notFound("رمز الدعوة غير صالح أو منتهي.");

    const members = await tx
      .select({ role: shopMembers.role })
      .from(shopMembers)
      .where(and(eq(shopMembers.shopId, invitation.shopId), eq(shopMembers.userId, userId), eq(shopMembers.status, "active")))
      .limit(1);
    if (members[0] && members[0].role !== "customer") {
      throw conflict("هذا الحساب مرتبط بالمحل بدور آخر.");
    }
    if (!members[0]) {
      await tx.insert(shopMembers).values({ shopId: invitation.shopId, userId, role: "customer" });
    }
    await tx
      .insert(customerUserLinks)
      .values({ customerId: invitation.customerId, userId })
      .onConflictDoNothing();
    const accepted = await tx
      .update(invitations)
      .set({ status: "accepted", acceptedAt: new Date() })
      .where(and(eq(invitations.id, invitation.id), eq(invitations.status, "pending")))
      .returning({ id: invitations.id });
    if (accepted.length === 0) throw conflict("استُخدم رمز الدعوة بالفعل.");
    return { shopId: invitation.shopId, customerId: invitation.customerId };
  });
}

export async function getCustomerIdForUser(
  db: Database,
  shopId: string,
  userId: string,
): Promise<string> {
  const rows = await db
    .select({ customerId: customerUserLinks.customerId })
    .from(customerUserLinks)
    .innerJoin(customerShopLinks, eq(customerShopLinks.customerId, customerUserLinks.customerId))
    .where(and(eq(customerUserLinks.userId, userId), eq(customerShopLinks.shopId, shopId), eq(customerShopLinks.status, "active")))
    .limit(1);
  const customerId = rows[0]?.customerId;
  if (!customerId) throw notFound("لا يوجد سجل عميل مرتبط بهذا الحساب في المحل.");
  return customerId;
}

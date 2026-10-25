import { and, eq } from "drizzle-orm";
import type { Database } from "../../db/index.js";
import {
  financialAdjustments,
  objections,
  objectionReplies,
  customerShopLinks,
  payments,
  purchaseReturns,
  purchases,
} from "../../db/schema.js";
import { randomUUID } from "node:crypto";
import { notFound } from "../../common/errors.js";

export interface ObjectionView {
  id: string;
  shopId: string;
  customerId: string;
  entityType: string;
  entityId: string;
  body: string;
  status: string;
  createdAt: string;
  updatedAt: string;
}

export async function createObjection(
  db: Database,
  shopId: string,
  customerId: string,
  body: { entityType: string; entityId: string; body: string },
): Promise<ObjectionView> {
  const links = await db
    .select({ id: customerShopLinks.id })
    .from(customerShopLinks)
    .where(and(eq(customerShopLinks.shopId, shopId), eq(customerShopLinks.customerId, customerId), eq(customerShopLinks.status, "active")))
    .limit(1);
  if (links.length === 0) throw notFound("العميل غير موجود.");
  const entityMatchesCustomer = await entityBelongsToCustomer(
    db,
    shopId,
    customerId,
    body.entityType,
    body.entityId,
  );
  if (!entityMatchesCustomer) {
    throw notFound("العملية غير موجودة لهذا العميل.");
  }
  const rows = await db
    .insert(objections)
    .values({ id: randomUUID(), shopId, customerId, entityType: body.entityType as any, entityId: body.entityId, body: body.body })
    .returning();
  const r = rows[0]!;
  return {
    id: r.id,
    shopId: r.shopId,
    customerId: r.customerId,
    entityType: r.entityType,
    entityId: r.entityId,
    body: r.body,
    status: r.status,
    createdAt: r.createdAt.toISOString(),
    updatedAt: r.updatedAt.toISOString(),
  };
}

async function entityBelongsToCustomer(
  db: Database,
  shopId: string,
  customerId: string,
  entityType: string,
  entityId: string,
): Promise<boolean> {
  const table = {
    purchase: purchases,
    payment: payments,
    purchase_return: purchaseReturns,
    financial_adjustment: financialAdjustments,
  }[entityType];
  if (!table) return false;
  const rows = await db
    .select({ id: table.id })
    .from(table)
    .where(
      and(
        eq(table.id, entityId),
        eq(table.shopId, shopId),
        eq(table.customerId, customerId),
      ),
    )
    .limit(1);
  return rows.length > 0;
}

export async function listShopObjections(db: Database, shopId: string, status?: string, customerId?: string) {
  let q = db.select().from(objections).where(eq(objections.shopId, shopId));
  const rows = await q;
  return rows
    .filter((r) => (!status || r.status === status) && (!customerId || r.customerId === customerId))
    .map((r) => ({
      id: r.id,
      shopId: r.shopId,
      customerId: r.customerId,
      entityType: r.entityType,
      entityId: r.entityId,
      body: r.body,
      status: r.status,
      createdAt: r.createdAt.toISOString(),
      updatedAt: r.updatedAt.toISOString(),
    }));
}

export async function replyToObjection(db: Database, shopId: string, objectionId: string, authorUserId: string, role: string, body: string) {
  const rows = await db.select().from(objections).where(and(eq(objections.id, objectionId), eq(objections.shopId, shopId))).limit(1);
  if (rows.length === 0) throw notFound("الاعتراض غير موجود.");
  await db.insert(objectionReplies).values({ objectionId, authorUserId, authorRole: role as any, body });
  return { ok: true };
}

export async function resolveObjection(db: Database, shopId: string, objectionId: string) {
  const rows = await db.update(objections).set({ status: "resolved", resolvedAt: new Date() }).where(and(eq(objections.id, objectionId), eq(objections.shopId, shopId))).returning();
  if (rows.length === 0) throw notFound("الاعتراض غير موجود.");
  return { ok: true };
}

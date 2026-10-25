// منطق وحدة التصحيحات المالية والإلغاءات (financial_adjustments).
//
// القواعد (docs/01 §4.3، docs/03 §6):
//  - التصحيح: kind=correction، amount ≠ 0 (موجب يزيد، سالب يخصم) + سبب إلزامي.
//  - الإلغاء: kind=cancellation، قيد عكسي بمبلغ = − (أثر العملية المتبقي)
//    = − (إجمالي العملية − مدفوعاتها − مرتجعاتها)، فتُصفّى مساهمة العملية من الرصيد.
//    العملية الأصلية **تبقى كما هي** (لا حذف ولا تعديل صامت).
//  - التصحيح السالب لا يجعل رصيد العميل سالبًا (منع رصيد سالب غير مبرَّر).
//  - كل إجراء يُسجَّل في سجل التدقيق (المستخدم/الوقت/السبب/قبل-بعد).
//  - معرّف ثابت + Idempotency-Key يمنعان التكرار (R-04/R-07).

import { and, eq, sql } from "drizzle-orm";
import { randomUUID } from "node:crypto";
import type { Database } from "../../db/index.js";
import {
  customerShopLinks,
  financialAdjustments,
  payments,
  purchaseReturns,
  purchases,
  syncOperations,
} from "../../db/schema.js";
import { AppError, notFound, badRequest } from "../../common/errors.js";
import { computeCustomerBalance } from "../../common/balance.js";
import { writeAuditLog } from "../../common/audit.js";

type DbExecutor = Database | Parameters<Parameters<Database["transaction"]>[0]>[0];

export interface AdjustmentView {
  id: string;
  shopId: string;
  customerId: string;
  relatedPurchaseId: string | null;
  kind: string;
  amount: string;
  reason: string;
  occurredAt: string;
  balanceAfter: string | null;
  createdAt: string;
  updatedAt: string;
}

type AdjustmentRow = {
  id: string;
  shopId: string;
  customerId: string;
  relatedPurchaseId: string | null;
  kind: string;
  amount: bigint;
  reason: string;
  occurredAt: Date;
  balanceAfter: bigint | null;
  createdAt: Date;
  updatedAt: Date;
};

function toAdjustmentView(row: AdjustmentRow): AdjustmentView {
  return {
    id: row.id,
    shopId: row.shopId,
    customerId: row.customerId,
    relatedPurchaseId: row.relatedPurchaseId,
    kind: row.kind,
    amount: row.amount.toString(),
    reason: row.reason,
    occurredAt: row.occurredAt.toISOString(),
    balanceAfter: row.balanceAfter === null ? null : row.balanceAfter.toString(),
    createdAt: row.createdAt.toISOString(),
    updatedAt: row.updatedAt.toISOString(),
  };
}

async function requireLinkedCustomer(
  db: DbExecutor,
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

export interface CreateAdjustmentInput {
  id?: string;
  customerId: string;
  relatedPurchaseId?: string;
  amount: number;
  reason: string;
  occurredAt?: string;
  idempotencyKey?: string;
}

// تسجيل تصحيح مالي ضمن معاملة واحدة.
export async function createAdjustment(
  db: Database,
  shopId: string,
  actorUserId: string,
  input: CreateAdjustmentInput,
): Promise<AdjustmentView> {
  return db.transaction(async (tx) => {
    await requireLinkedCustomer(tx, shopId, input.customerId);

    const amount = BigInt(input.amount);
    if (amount === 0n) throw badRequest("المبلغ لا يكون صفرًا.");

    // ربط اختياري بعملية: يجب أن تكون لنفس المحل والعميل.
    if (input.relatedPurchaseId) {
      const rows = await tx
        .select({ id: purchases.id })
        .from(purchases)
        .where(
          and(
            eq(purchases.shopId, shopId),
            eq(purchases.id, input.relatedPurchaseId),
            eq(purchases.customerId, input.customerId),
          ),
        )
        .limit(1);
      if (rows.length === 0) throw notFound("العملية المرتبطة غير موجودة.");
    }

    // منع التكرار (R-07).
    if (input.idempotencyKey) {
      const existingOp = await tx
        .select({ entityId: syncOperations.entityId })
        .from(syncOperations)
        .where(
          and(
            eq(syncOperations.shopId, shopId),
            eq(syncOperations.idempotencyKey, input.idempotencyKey),
          ),
        )
        .limit(1);
      const priorId = existingOp[0]?.entityId;
      if (priorId) {
        const prior = await tx
          .select()
          .from(financialAdjustments)
          .where(eq(financialAdjustments.id, priorId))
          .limit(1);
        if (prior[0]) return toAdjustmentView(prior[0]);
      }
    }

    const adjustmentId = input.id ?? randomUUID();
    const priorById = await tx
      .select()
      .from(financialAdjustments)
      .where(
        and(
          eq(financialAdjustments.shopId, shopId),
          eq(financialAdjustments.id, adjustmentId),
        ),
      )
      .limit(1);
    if (priorById[0]) return toAdjustmentView(priorById[0]);

    // التصحيح السالب لا يجعل الرصيد سالبًا.
    if (amount < 0n) {
      const balance = await computeCustomerBalance(tx, shopId, input.customerId);
      if (-amount > balance) {
        throw badRequest("التصحيح السالب يتجاوز الرصيد الحالي للعميل.");
      }
    }

    const occurredAt = input.occurredAt ? new Date(input.occurredAt) : new Date();

    const inserted = await tx
      .insert(financialAdjustments)
      .values({
        id: adjustmentId,
        shopId,
        customerId: input.customerId,
        relatedPurchaseId: input.relatedPurchaseId ?? null,
        kind: "correction",
        amount,
        reason: input.reason,
        occurredAt,
        createdBy: actorUserId,
      })
      .returning();
    const created = inserted[0];
    if (!created) throw new Error("فشل تسجيل التصحيح");

    const balanceAfter = await computeCustomerBalance(tx, shopId, input.customerId);
    const withBalance = await tx
      .update(financialAdjustments)
      .set({ balanceAfter })
      .where(eq(financialAdjustments.id, created.id))
      .returning();

    await writeAuditLog(tx, {
      shopId,
      actorUserId,
      action: "adjustment.create",
      entityType: "financial_adjustment",
      entityId: created.id,
      after: {
        customerId: input.customerId,
        kind: "correction",
        amount: input.amount,
        reason: input.reason,
        balanceAfter: balanceAfter.toString(),
      },
    });

    if (input.idempotencyKey) {
      await tx.insert(syncOperations).values({
        shopId,
        actorUserId,
        idempotencyKey: input.idempotencyKey,
        operationType: "push",
        entityType: "financial_adjustment",
        entityId: created.id,
        status: "accepted",
        requestPayload: { customerId: input.customerId, amount: input.amount },
      });
    }

    return toAdjustmentView(withBalance[0] ?? created);
  });
}

export interface CancelPurchaseInput {
  id?: string;
  reason: string;
  occurredAt?: string;
  idempotencyKey?: string;
  // إصدار العملية المتوقع (قفل تفاؤلي) — اختياري.
  version?: number;
}

// إلغاء عملية شراء: قيد عكسي بمبلغ = − متبقي العملية؛ الأصل يبقى كما هو.
export async function cancelPurchase(
  db: Database,
  shopId: string,
  purchaseId: string,
  actorUserId: string,
  input: CancelPurchaseInput,
): Promise<AdjustmentView> {
  return db.transaction(async (tx) => {
    const rows = await tx
      .select()
      .from(purchases)
      .where(and(eq(purchases.shopId, shopId), eq(purchases.id, purchaseId)))
      .limit(1);
    const purchase = rows[0];
    if (!purchase) throw notFound("العملية غير موجودة.");
    if (purchase.status !== "active") {
      throw badRequest("العملية ملغاة مسبقًا.");
    }

    // قفل تفاؤلي: التحقق من الإصدار.
    if (input.version !== undefined && purchase.version !== input.version) {
      throw new AppError(
        409,
        "CONFLICT",
        "تم تعديل العملية من قبل مستخدم آخر. يرجى تحديث البيانات والمحاولة مرة أخرى.",
        {
          serverVersion: purchase.version,
          clientVersion: input.version,
        },
      );
    }

    // منع الإلغاء المزدوج: قيد إلغاء سابق لنفس العملية.
    const priorCancel = await tx
      .select({ id: financialAdjustments.id })
      .from(financialAdjustments)
      .where(
        and(
          eq(financialAdjustments.shopId, shopId),
          eq(financialAdjustments.relatedPurchaseId, purchaseId),
          eq(financialAdjustments.kind, "cancellation"),
        ),
      )
      .limit(1);
    if (priorCancel.length > 0) {
      throw badRequest("العملية ملغاة مسبقًا.");
    }

    // منع التكرار (R-07) لطلب الإلغاء نفسه.
    if (input.idempotencyKey) {
      const existingOp = await tx
        .select({ entityId: syncOperations.entityId })
        .from(syncOperations)
        .where(
          and(
            eq(syncOperations.shopId, shopId),
            eq(syncOperations.idempotencyKey, input.idempotencyKey),
          ),
        )
        .limit(1);
      const priorId = existingOp[0]?.entityId;
      if (priorId) {
        const prior = await tx
          .select()
          .from(financialAdjustments)
          .where(eq(financialAdjustments.id, priorId))
          .limit(1);
        if (prior[0]) return toAdjustmentView(prior[0]);
      }
    }

    const paidRows = await tx
      .select({ total: sql<string>`coalesce(sum(${payments.amount}), 0)` })
      .from(payments)
      .where(eq(payments.purchaseId, purchaseId));
    const returnRows = await tx
      .select({ total: sql<string>`coalesce(sum(${purchaseReturns.amount}), 0)` })
      .from(purchaseReturns)
      .where(eq(purchaseReturns.purchaseId, purchaseId));
    const paid = BigInt(paidRows[0]?.total ?? "0");
    const returned = BigInt(returnRows[0]?.total ?? "0");
    // أثر العملية المتبقي = الإجمالي − مدفوعاتها − مرتجعاتها.
    const remainingEffect = purchase.totalAmount - paid - returned;
    if (remainingEffect === 0n) {
      throw badRequest("لا يوجد رصيد متبقٍ لإلغائه على هذه العملية.");
    }
    // القيد العكسي = سالب الأثر المتبقي.
    const reversal = -remainingEffect;

    const occurredAt = input.occurredAt ? new Date(input.occurredAt) : new Date();
    const adjustmentId = input.id ?? randomUUID();

    const inserted = await tx
      .insert(financialAdjustments)
      .values({
        id: adjustmentId,
        shopId,
        customerId: purchase.customerId,
        relatedPurchaseId: purchaseId,
        kind: "cancellation",
        amount: reversal,
        reason: input.reason,
        occurredAt,
        createdBy: actorUserId,
      })
      .returning();
    const created = inserted[0];
    if (!created) throw new Error("فشل تسجيل إلغاء العملية");

    const balanceAfter = await computeCustomerBalance(tx, shopId, purchase.customerId);
    const withBalance = await tx
      .update(financialAdjustments)
      .set({ balanceAfter })
      .where(eq(financialAdjustments.id, created.id))
      .returning();

    await writeAuditLog(tx, {
      shopId,
      actorUserId,
      action: "purchase.cancel",
      entityType: "purchase",
      entityId: purchaseId,
      before: {
        totalAmount: purchase.totalAmount.toString(),
        paidAmount: paid.toString(),
        returnedAmount: returned.toString(),
        status: purchase.status,
      },
      after: {
        kind: "cancellation",
        amount: reversal.toString(),
        reason: input.reason,
        balanceAfter: balanceAfter.toString(),
      },
    });

    if (input.idempotencyKey) {
      await tx.insert(syncOperations).values({
        shopId,
        actorUserId,
        idempotencyKey: input.idempotencyKey,
        operationType: "push",
        entityType: "financial_adjustment",
        entityId: created.id,
        status: "accepted",
        requestPayload: { purchaseId, reversalAmount: Number(reversal) },
      });
    }

    return toAdjustmentView(withBalance[0] ?? created);
  });
}

export async function listShopAdjustments(
  db: Database,
  shopId: string,
  customerId?: string,
): Promise<AdjustmentView[]> {
  if (customerId) await requireLinkedCustomer(db, shopId, customerId);
  const rows = await db
    .select()
    .from(financialAdjustments)
    .where(
      customerId
        ? and(
            eq(financialAdjustments.shopId, shopId),
            eq(financialAdjustments.customerId, customerId),
          )
        : eq(financialAdjustments.shopId, shopId),
    )
    .orderBy(
      sql`${financialAdjustments.occurredAt} desc, ${financialAdjustments.createdAt} desc`,
    );
  return rows.map(toAdjustmentView);
}

export async function getAdjustmentForShop(
  db: Database,
  shopId: string,
  adjustmentId: string,
): Promise<AdjustmentView> {
  const rows = await db
    .select()
    .from(financialAdjustments)
    .where(
      and(
        eq(financialAdjustments.shopId, shopId),
        eq(financialAdjustments.id, adjustmentId),
      ),
    )
    .limit(1);
  const row = rows[0];
  if (!row) throw notFound("التصحيح غير موجود.");
  return toAdjustmentView(row);
}

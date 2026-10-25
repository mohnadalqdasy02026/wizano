// منطق وحدة المرتجعات — قيد يخصم قيمة المرتجع من رصيد العميل، مرتبط بالعملية الأصلية.
//
// القواعد (docs/01 §4.3، docs/03 §6):
//  - المرتجع قيد جديد لا يعدّل العملية الأصلية؛ الأصل يبقى كما هو.
//  - amount > 0 (يُفرض على المدخلات وعلى القاعدة).
//  - لا يتجاوز المرتجع متبقي العملية الأصلية = الإجمالي − مدفوعاتها − مرتجعاتها السابقة.
//  - أثر المرتجع على الرصيد: − المبلغ.
//  - يُسجَّل في سجل التدقيق (المستخدم/الوقت/السبب/الأصل/الأثر).
//  - معرّف ثابت (UUIDv7 من العميل) + Idempotency-Key يمنعان التكرار (R-04/R-07).

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
import { notFound, badRequest } from "../../common/errors.js";
import { computeCustomerBalance } from "../../common/balance.js";
import { writeAuditLog } from "../../common/audit.js";

type DbExecutor = Database | Parameters<Parameters<Database["transaction"]>[0]>[0];

export interface ReturnView {
  id: string;
  shopId: string;
  customerId: string;
  purchaseId: string;
  amount: string;
  reason: string | null;
  occurredAt: string;
  balanceAfter: string | null;
  createdAt: string;
  updatedAt: string;
}

type ReturnRow = {
  id: string;
  shopId: string;
  customerId: string;
  purchaseId: string;
  amount: bigint;
  reason: string | null;
  occurredAt: Date;
  balanceAfter: bigint | null;
  createdAt: Date;
  updatedAt: Date;
};

function toReturnView(row: ReturnRow): ReturnView {
  return {
    id: row.id,
    shopId: row.shopId,
    customerId: row.customerId,
    purchaseId: row.purchaseId,
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

export interface CreateReturnInput {
  id?: string;
  purchaseId: string;
  amount: number;
  reason?: string;
  occurredAt?: string;
  idempotencyKey?: string;
}

// تسجيل مرتجع مرتبط بعملية شراء ضمن معاملة واحدة.
// عند إعادة الإرسال بنفس المعرّف أو بمفتاح idempotency مكرَّر: يعيد المرتجع القائم.
export async function createReturn(
  db: Database,
  shopId: string,
  actorUserId: string,
  input: CreateReturnInput,
): Promise<ReturnView> {
  return db.transaction(async (tx) => {
    // العملية الأصلية إلزامية، لنفس المحل، ونشطة.
    const rows = await tx
      .select()
      .from(purchases)
      .where(
        and(eq(purchases.shopId, shopId), eq(purchases.id, input.purchaseId)),
      )
      .limit(1);
    const purchase = rows[0];
    if (!purchase) throw notFound("العملية الأصلية غير موجودة.");
    if (purchase.status !== "active") {
      throw badRequest("لا يمكن تسجيل مرتجع على عملية ملغاة.");
    }

    // العملية الملغاة (قيد عكسي سابق) لا تقبل مرتجعًا — منعًا للخصم المزدوج.
    const priorCancel = await tx
      .select({ id: financialAdjustments.id })
      .from(financialAdjustments)
      .where(
        and(
          eq(financialAdjustments.shopId, shopId),
          eq(financialAdjustments.relatedPurchaseId, input.purchaseId),
          eq(financialAdjustments.kind, "cancellation"),
        ),
      )
      .limit(1);
    if (priorCancel.length > 0) {
      throw badRequest("لا يمكن تسجيل مرتجع على عملية ملغاة.");
    }

    await requireLinkedCustomer(tx, shopId, purchase.customerId);

    // منع التكرار عبر مفتاح idempotency (R-07).
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
          .from(purchaseReturns)
          .where(eq(purchaseReturns.id, priorId))
          .limit(1);
        if (prior[0]) return toReturnView(prior[0]);
      }
    }

    // معرّف ثابت من العميل: إن وُجد سابقًا نعيده بدل إنشاء نسخة جديدة (R-04).
    const returnId = input.id ?? randomUUID();
    const priorById = await tx
      .select()
      .from(purchaseReturns)
      .where(
        and(eq(purchaseReturns.shopId, shopId), eq(purchaseReturns.id, returnId)),
      )
      .limit(1);
    if (priorById[0]) return toReturnView(priorById[0]);

    const amount = BigInt(input.amount);

    // متبقي العملية = الإجمالي − مدفوعاتها − مرتجعاتها السابقة.
    const paidRows = await tx
      .select({ total: sql<string>`coalesce(sum(${payments.amount}), 0)` })
      .from(payments)
      .where(eq(payments.purchaseId, input.purchaseId));
    const priorReturns = await tx
      .select({ total: sql<string>`coalesce(sum(${purchaseReturns.amount}), 0)` })
      .from(purchaseReturns)
      .where(eq(purchaseReturns.purchaseId, input.purchaseId));
    const paidOnPurchase = BigInt(paidRows[0]?.total ?? "0");
    const returnedOnPurchase = BigInt(priorReturns[0]?.total ?? "0");
    const purchaseRemaining =
      purchase.totalAmount - paidOnPurchase - returnedOnPurchase;
    if (amount > purchaseRemaining) {
      throw badRequest("قيمة المرتجع تتجاوز المتبقي على العملية.");
    }

    const occurredAt = input.occurredAt ? new Date(input.occurredAt) : new Date();

    const inserted = await tx
      .insert(purchaseReturns)
      .values({
        id: returnId,
        shopId,
        customerId: purchase.customerId,
        purchaseId: purchase.id,
        amount,
        reason: input.reason ?? null,
        occurredAt,
        createdBy: actorUserId,
      })
      .returning();
    const created = inserted[0];
    if (!created) throw new Error("فشل تسجيل المرتجع");

    const balanceAfter = await computeCustomerBalance(tx, shopId, purchase.customerId);
    const withBalance = await tx
      .update(purchaseReturns)
      .set({ balanceAfter })
      .where(eq(purchaseReturns.id, created.id))
      .returning();

    // سجل التدقيق: الأثر = − المبلغ (R-06 #6).
    await writeAuditLog(tx, {
      shopId,
      actorUserId,
      action: "purchase.return",
      entityType: "purchase_return",
      entityId: created.id,
      after: {
        purchaseId: purchase.id,
        customerId: purchase.customerId,
        amount: input.amount,
        effect: -input.amount,
        reason: input.reason ?? null,
        balanceAfter: balanceAfter.toString(),
      },
    });

    // تسجيل عملية المزامنة عند استخدام مفتاح idempotency (R-07).
    if (input.idempotencyKey) {
      await tx.insert(syncOperations).values({
        shopId,
        actorUserId,
        idempotencyKey: input.idempotencyKey,
        operationType: "push",
        entityType: "purchase_return",
        entityId: created.id,
        status: "accepted",
        requestPayload: {
          purchaseId: purchase.id,
          amount: input.amount,
        },
      });
    }

    return toReturnView(withBalance[0] ?? created);
  });
}

// مرتجعات المحل (اختياريًا لعميل محدَّد)، الأحدث أولًا.
export async function listShopReturns(
  db: Database,
  shopId: string,
  customerId?: string,
): Promise<ReturnView[]> {
  if (customerId) await requireLinkedCustomer(db, shopId, customerId);
  const rows = await db
    .select()
    .from(purchaseReturns)
    .where(
      customerId
        ? and(
            eq(purchaseReturns.shopId, shopId),
            eq(purchaseReturns.customerId, customerId),
          )
        : eq(purchaseReturns.shopId, shopId),
    )
    .orderBy(sql`${purchaseReturns.occurredAt} desc, ${purchaseReturns.createdAt} desc`);
  return rows.map(toReturnView);
}

export async function getReturnForShop(
  db: Database,
  shopId: string,
  returnId: string,
): Promise<ReturnView> {
  const rows = await db
    .select()
    .from(purchaseReturns)
    .where(
      and(eq(purchaseReturns.shopId, shopId), eq(purchaseReturns.id, returnId)),
    )
    .limit(1);
  const row = rows[0];
  if (!row) throw notFound("المرتجع غير موجود.");
  return toReturnView(row);
}

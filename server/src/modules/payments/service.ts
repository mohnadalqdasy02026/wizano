// منطق وحدة المدفوعات — تسجيل دفعة على حساب عميل (اختياريًا مرتبطة بعملية شراء).
//
// القواعد المطبَّقة (docs/01 §4.2، docs/07 §7):
//  - الدفعة قيد مستقل يخصم من رصيد العميل (لا تعديل يدوي للرصيد).
//  - رصيد العميل = Σ المشتريات − Σ المدفوعات (D-09)؛ يُخزَّن «الرصيد بعد العملية».
//  - amount > 0 (يُفرض على المدخلات وعلى القاعدة).
//  - دفعة عامة لا تجعل الرصيد سالبًا (منع «دفعة مقدمة زائدة» — خارج النطاق §4.1).
//  - دفعة مرتبطة بعملية لا تتجاوز متبقي تلك العملية.
//  - رقم الدفعة فريد ضمن المحل عبر shop_counters (kind = payment).
//  - معرّف ثابت (UUIDv7 من العميل) + Idempotency-Key يمنعان التكرار (R-04/R-07).

import { and, eq, sql } from "drizzle-orm";
import { randomUUID } from "node:crypto";
import type { Database } from "../../db/index.js";
import {
  customerShopLinks,
  payments,
  purchases,
  shopCounters,
  syncOperations,
} from "../../db/schema.js";
import { notFound, badRequest } from "../../common/errors.js";
import { computeCustomerBalance } from "../../common/balance.js";

type DbExecutor = Database | Parameters<Parameters<Database["transaction"]>[0]>[0];

export interface PaymentView {
  id: string;
  shopId: string;
  customerId: string;
  purchaseId: string | null;
  amount: string;
  paidAt: string;
  shopSeq: string | null;
  notes: string | null;
  balanceAfter: string | null;
  createdAt: string;
  updatedAt: string;
}

type PaymentRow = {
  id: string;
  shopId: string;
  customerId: string;
  purchaseId: string | null;
  amount: bigint;
  paidAt: Date;
  shopSeq: bigint | null;
  notes: string | null;
  balanceAfter: bigint | null;
  createdAt: Date;
  updatedAt: Date;
};

function toPaymentView(row: PaymentRow): PaymentView {
  return {
    id: row.id,
    shopId: row.shopId,
    customerId: row.customerId,
    purchaseId: row.purchaseId,
    amount: row.amount.toString(),
    paidAt: row.paidAt.toISOString(),
    shopSeq: row.shopSeq === null ? null : row.shopSeq.toString(),
    notes: row.notes,
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

async function nextShopSeq(
  tx: DbExecutor,
  shopId: string,
  kind: string,
): Promise<bigint> {
  const rows = await tx
    .update(shopCounters)
    .set({ lastValue: sql`${shopCounters.lastValue} + 1` })
    .where(and(eq(shopCounters.shopId, shopId), eq(shopCounters.kind, kind)))
    .returning({ lastValue: shopCounters.lastValue });
  const row = rows[0];
  if (!row) throw new Error(`عدّاد المحل مفقود للنوع: ${kind}`);
  return row.lastValue;
}

// رصيد العميل = Σ مشتريات (نشطة) − Σ مدفوعات − Σ مرتجعات ± Σ تصحيحات (D-09).
async function computeBalance(
  tx: DbExecutor,
  shopId: string,
  customerId: string,
): Promise<bigint> {
  return computeCustomerBalance(tx, shopId, customerId);
}

export interface CreatePaymentInput {
  id?: string;
  customerId: string;
  purchaseId?: string;
  amount: number;
  notes?: string;
  paidAt?: string;
  idempotencyKey?: string;
}

// تسجيل دفعة على حساب عميل ضمن معاملة واحدة.
// عند إعادة الإرسال بنفس المعرّف أو بمفتاح idempotency مكرَّر: يعيد الدفعة القائمة.
export async function createPayment(
  db: Database,
  shopId: string,
  actorUserId: string,
  input: CreatePaymentInput,
): Promise<PaymentView> {
  return db.transaction(async (tx) => {
    await requireLinkedCustomer(tx, shopId, input.customerId);

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
          .from(payments)
          .where(eq(payments.id, priorId))
          .limit(1);
        if (prior[0]) return toPaymentView(prior[0]);
      }
    }

    // معرّف ثابت من العميل: إن وُجد سابقًا نعيده بدل إنشاء نسخة جديدة (R-04).
    const paymentId = input.id ?? randomUUID();
    const priorById = await tx
      .select()
      .from(payments)
      .where(and(eq(payments.shopId, shopId), eq(payments.id, paymentId)))
      .limit(1);
    if (priorById[0]) return toPaymentView(priorById[0]);

    const amount = BigInt(input.amount);

    // دفعة مرتبطة بعملية: يجب أن تكون العملية لنفس المحل والعميل، وألا تتجاوز متبقيها.
    if (input.purchaseId) {
      const rows = await tx
        .select()
        .from(purchases)
        .where(
          and(
            eq(purchases.shopId, shopId),
            eq(purchases.id, input.purchaseId),
            eq(purchases.customerId, input.customerId),
          ),
        )
        .limit(1);
      const purchase = rows[0];
      if (!purchase) throw notFound("العملية غير موجودة.");

      const alreadyPaid = await tx
        .select({ total: sql<string>`coalesce(sum(${payments.amount}), 0)` })
        .from(payments)
        .where(eq(payments.purchaseId, input.purchaseId));
      const paidOnPurchase = BigInt(alreadyPaid[0]?.total ?? "0");
      const purchaseRemaining = purchase.totalAmount - paidOnPurchase;
      if (amount > purchaseRemaining) {
        throw badRequest("المبلغ يتجاوز المتبقي على العملية.");
      }
    } else {
      // دفعة عامة: لا تجعل رصيد العميل سالبًا (منع الدفعة المقدمة الزائدة §4.1).
      const balance = await computeBalance(tx, shopId, input.customerId);
      if (amount > balance) {
        throw badRequest("المبلغ يتجاوز إجمالي المتبقي على العميل.");
      }
    }

    const shopSeq = await nextShopSeq(tx, shopId, "payment");
    const paidAt = input.paidAt ? new Date(input.paidAt) : new Date();

    const inserted = await tx
      .insert(payments)
      .values({
        id: paymentId,
        shopId,
        customerId: input.customerId,
        purchaseId: input.purchaseId ?? null,
        amount,
        paidAt,
        shopSeq,
        notes: input.notes ?? null,
        createdBy: actorUserId,
      })
      .returning();
    const payment = inserted[0];
    if (!payment) throw new Error("فشل تسجيل الدفعة");

    const balanceAfter = await computeBalance(tx, shopId, input.customerId);
    const withBalance = await tx
      .update(payments)
      .set({ balanceAfter })
      .where(eq(payments.id, payment.id))
      .returning();

    // تسجيل عملية المزامنة عند استخدام مفتاح idempotency (R-07).
    if (input.idempotencyKey) {
      await tx.insert(syncOperations).values({
        shopId,
        actorUserId,
        idempotencyKey: input.idempotencyKey,
        operationType: "push",
        entityType: "payment",
        entityId: payment.id,
        status: "accepted",
        requestPayload: {
          customerId: input.customerId,
          purchaseId: input.purchaseId ?? null,
          amount: input.amount,
        },
      });
    }

    return toPaymentView(withBalance[0] ?? payment);
  });
}

// دفعات المحل (اختياريًا لعميل محدَّد)، الأحدث أولًا.
export async function listShopPayments(
  db: Database,
  shopId: string,
  customerId?: string,
): Promise<PaymentView[]> {
  if (customerId) await requireLinkedCustomer(db, shopId, customerId);
  const rows = await db
    .select()
    .from(payments)
    .where(
      customerId
        ? and(eq(payments.shopId, shopId), eq(payments.customerId, customerId))
        : eq(payments.shopId, shopId),
    )
    .orderBy(sql`${payments.paidAt} desc, ${payments.createdAt} desc`);
  return rows.map(toPaymentView);
}

export async function getPaymentForShop(
  db: Database,
  shopId: string,
  paymentId: string,
): Promise<PaymentView> {
  const rows = await db
    .select()
    .from(payments)
    .where(and(eq(payments.shopId, shopId), eq(payments.id, paymentId)))
    .limit(1);
  const payment = rows[0];
  if (!payment) throw notFound("الدفعة غير موجودة.");
  return toPaymentView(payment);
}

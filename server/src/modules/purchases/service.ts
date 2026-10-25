// منطق وحدة المشتريات الآجلة — إنشاء عملية شراء مع الدفعة المرتبطة والعدّادات.
//
// القواعد المطبَّقة (docs/01 §4.1، docs/07 §4):
//  - المتبقي = الإجمالي − المدفوع (يُحسب آليًا ويُخزَّن كقيمة مشتقة).
//  - القيود: إجمالي ≥ 0، مدفوع ≥ 0، مدفوع ≤ إجمالي (تُفرض أيضًا على القاعدة).
//  - رقم العملية فريد ضمن المحل عبر shop_counters (kind = purchase/payment).
//  - المبلغ المدفوع وقت الشراء يُسجَّل دفعة مستقلة مرتبطة بالعملية (منع الحساب المزدوج).
//  - معرّف الثابت (UUIDv7 من العميل) + Idempotency-Key يمنعان التكرار (R-04/R-07).
//  - balance_after = Σ المشتريات − Σ المدفوعات (مشتق قابل لإعادة الحساب — D-09).

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
import { notFound } from "../../common/errors.js";
import { computeCustomerBalance } from "../../common/balance.js";

// نوع المنفّذ: قاعدة البيانات أو معاملة داخلها (نفس واجهة الاستعلام).
type DbExecutor = Database | Parameters<Parameters<Database["transaction"]>[0]>[0];

export interface PurchaseView {
  id: string;
  shopId: string;
  customerId: string;
  shopSeq: string;
  occurredAt: string;
  itemsText: string;
  totalAmount: string;
  paidAmount: string;
  remainingAmount: string;
  notes: string | null;
  status: string;
  statusReason: string | null;
  balanceAfter: string | null;
  version: number;
  createdAt: string;
  updatedAt: string;
}

type PurchaseRow = {
  id: string;
  shopId: string;
  customerId: string;
  shopSeq: bigint;
  occurredAt: Date;
  itemsText: string;
  totalAmount: bigint;
  paidAmount: bigint;
  remainingAmount: bigint;
  notes: string | null;
  status: string;
  statusReason: string | null;
  balanceAfter: bigint | null;
  version: number;
  createdAt: Date;
  updatedAt: Date;
};

function toPurchaseView(row: PurchaseRow): PurchaseView {
  return {
    id: row.id,
    shopId: row.shopId,
    customerId: row.customerId,
    shopSeq: row.shopSeq.toString(),
    occurredAt: row.occurredAt.toISOString(),
    itemsText: row.itemsText,
    totalAmount: row.totalAmount.toString(),
    paidAmount: row.paidAmount.toString(),
    remainingAmount: row.remainingAmount.toString(),
    notes: row.notes,
    status: row.status,
    statusReason: row.statusReason,
    balanceAfter: row.balanceAfter === null ? null : row.balanceAfter.toString(),
    version: row.version,
    createdAt: row.createdAt.toISOString(),
    updatedAt: row.updatedAt.toISOString(),
  };
}

// يتحقق أن العميل مرتبط فعليًا بالمحل؛ وإلا 404 موحّد (لا نكشف وجوده).
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

// يزيد عدّاد المحل للنوع المطلوب ويعيد القيمة الجديدة (ضمن المعاملة).
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

// يحسب رصيد العميل المشتق بعد العملية (المشتريات − المدفوعات − المرتجعات ± التصحيحات).
async function computeBalance(
  tx: DbExecutor,
  shopId: string,
  customerId: string,
): Promise<bigint> {
  return computeCustomerBalance(tx, shopId, customerId);
}

export interface CreatePurchaseInput {
  id?: string;
  customerId: string;
  itemsText: string;
  totalAmount: number;
  paidAmount: number;
  notes?: string;
  occurredAt?: string;
  idempotencyKey?: string;
}

// إنشاء عملية شراء (+ دفعة مرتبطة إن وُجد مدفوع) ضمن معاملة واحدة.
// عند إعادة الإرسال بنفس المعرّف أو بمفتاح idempotency مكرَّر: يعيد العملية القائمة (لا تكرار).
export async function createPurchase(
  db: Database,
  shopId: string,
  actorUserId: string,
  input: CreatePurchaseInput,
): Promise<PurchaseView> {
  return db.transaction(async (tx) => {
    await requireLinkedCustomer(tx, shopId, input.customerId);

    // منع التكرار عبر مفتاح idempotency (R-07): مفتاح مستخدم سابقًا ⇒ نعيد العملية نفسها.
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
          .from(purchases)
          .where(eq(purchases.id, priorId))
          .limit(1);
        if (prior[0]) return toPurchaseView(prior[0]);
      }
    }

    // معرّف ثابت من العميل: إن وُجد سابقًا نعيده بدل إنشاء نسخة جديدة (R-04).
    const purchaseId = input.id ?? randomUUID();
    const priorById = await tx
      .select()
      .from(purchases)
      .where(and(eq(purchases.shopId, shopId), eq(purchases.id, purchaseId)))
      .limit(1);
    if (priorById[0]) return toPurchaseView(priorById[0]);

    const shopSeq = await nextShopSeq(tx, shopId, "purchase");
    const total = BigInt(input.totalAmount);
    const paid = BigInt(input.paidAmount);
    const remaining = total - paid;
    const occurredAt = input.occurredAt ? new Date(input.occurredAt) : new Date();

    const inserted = await tx
      .insert(purchases)
      .values({
        id: purchaseId,
        shopId,
        customerId: input.customerId,
        shopSeq,
        occurredAt,
        itemsText: input.itemsText,
        totalAmount: total,
        paidAmount: paid,
        remainingAmount: remaining,
        notes: input.notes ?? null,
        createdBy: actorUserId,
      })
      .returning();
    const purchase = inserted[0];
    if (!purchase) throw new Error("فشل إنشاء عملية الشراء");

    // المبلغ المدفوع وقت الشراء ⇒ دفعة مستقلة مرتبطة بالعملية (منع الحساب المزدوج).
    if (paid > 0n) {
      const paymentSeq = await nextShopSeq(tx, shopId, "payment");
      await tx.insert(payments).values({
        id: randomUUID(),
        shopId,
        customerId: input.customerId,
        purchaseId: purchase.id,
        amount: paid,
        paidAt: occurredAt,
        shopSeq: paymentSeq,
        notes: "دفعة وقت الشراء",
        createdBy: actorUserId,
      });
    }

    const balanceAfter = await computeBalance(tx, shopId, input.customerId);
    const withBalance = await tx
      .update(purchases)
      .set({ balanceAfter })
      .where(eq(purchases.id, purchase.id))
      .returning();

    // تسجيل عملية المزامنة عند استخدام مفتاح idempotency (R-07).
    if (input.idempotencyKey) {
      await tx.insert(syncOperations).values({
        shopId,
        actorUserId,
        idempotencyKey: input.idempotencyKey,
        operationType: "push",
        entityType: "purchase",
        entityId: purchase.id,
        status: "accepted",
        requestPayload: {
          customerId: input.customerId,
          totalAmount: input.totalAmount,
          paidAmount: input.paidAmount,
        },
      });
    }

    return toPurchaseView(withBalance[0] ?? purchase);
  });
}

// مشتريات المحل (اختياريًا لعميل محدَّد)، الأحدث أولًا.
export async function listShopPurchases(
  db: Database,
  shopId: string,
  customerId?: string,
): Promise<PurchaseView[]> {
  if (customerId) await requireLinkedCustomer(db, shopId, customerId);
  const rows = await db
    .select()
    .from(purchases)
    .where(
      customerId
        ? and(eq(purchases.shopId, shopId), eq(purchases.customerId, customerId))
        : eq(purchases.shopId, shopId),
    )
    .orderBy(sql`${purchases.occurredAt} desc, ${purchases.createdAt} desc`);
  return rows.map(toPurchaseView);
}

export async function getPurchaseForShop(
  db: Database,
  shopId: string,
  purchaseId: string,
): Promise<PurchaseView> {
  const rows = await db
    .select()
    .from(purchases)
    .where(and(eq(purchases.shopId, shopId), eq(purchases.id, purchaseId)))
    .limit(1);
  const purchase = rows[0];
  if (!purchase) throw notFound("العملية غير موجودة.");
  return toPurchaseView(purchase);
}

// يُصدَّر لأجل الاختبارات: التحقق من ربط قائمة عملاء.
export { requireLinkedCustomer as _requireLinkedCustomer };

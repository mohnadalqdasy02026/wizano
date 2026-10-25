// منطق وحدة كشف الحساب — تجميع عمليات العميل (مشتريات + مدفوعات) زمنيًا مع رصيد جارٍ.
//
// القواعد (docs/01 §4.2، docs/03 §5):
//  - الرصيد يُحسب من السجلات المالية فقط ولا يُعدَّل يدويًا.
//  - الترتيب الزمني للعمليات، والرصيد الجاري بعد كل عملية (شامل النطاق المطلوب).
//  - أثر العملية: مشتريات + الإجمالي، دفعة − المبلغ.
//    (المرتجعات/التصحيحات تُضاف في المرحلة 11.)
//  - النطاق الزمني/النوعي يؤثر على العرض فقط؛ الرصيد الجاري يبدأ من صافي ما قبل نقطة البداية،
//    فيبقى الرصيد النهائي مطابقًا للرصيد الحقيقي للعميل بغض النظر عن التصفية.

import { and, eq } from "drizzle-orm";
import type { Database } from "../../db/index.js";
import {
  customerShopLinks,
  financialAdjustments,
  payments,
  purchaseReturns,
  purchases,
} from "../../db/schema.js";
import { notFound } from "../../common/errors.js";
import { customerBalanceBreakdown } from "../../common/balance.js";

export type StatementEntryType =
  | "purchase"
  | "payment"
  | "return"
  | "adjustment";

export interface StatementEntry {
  id: string;
  type: StatementEntryType;
  shopSeq: string | null;
  occurredAt: string;
  description: string;
  // الأثر على الرصيد (موجب يزيد، سالب يخصم).
  effect: string;
  // الرصيد الجاري بعد هذه العملية.
  balanceAfter: string;
  status: string;
  // مرجع العملية المرتبطة (للدفعات/المرتجعات/الإلغاءات المرتبطة بعملية شراء).
  purchaseId: string | null;
  // نوع التصحيح (correction/cancellation) — للسطور من نوع adjustment.
  adjustmentKind: string | null;
}

export interface StatementView {
  customerId: string;
  // إجمالي المشتريات (النشطة) — بلا تصفية.
  totalPurchases: string;
  // إجمالي المدفوعات — بلا تصفية.
  totalPayments: string;
  // إجمالي المرتجعات — بلا تصفية.
  totalReturns: string;
  // صافي التصحيحات المالية (±) — بلا تصفية.
  totalAdjustments: string;
  // الرصيد الحالي = Σ مشتريات − Σ مدفوعات − Σ مرتجعات ± Σ تصحيحات.
  balance: string;
  entries: StatementEntry[];
}

export interface StatementFilter {
  type?: "all" | "purchase" | "payment" | "return" | "adjustment";
  from?: string;
  to?: string;
}

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

// سطر خام موحّد قبل الترتيب/التراكم.
interface RawLine {
  id: string;
  type: StatementEntryType;
  shopSeq: bigint | null;
  occurredAt: Date;
  description: string;
  signedAmount: bigint; // مشتريات: + الإجمالي، دفعة/مرتجع: − المبلغ، تصحيح: ± المبلغ
  status: string;
  purchaseId: string | null;
  adjustmentKind: string | null;
}

// أولوية الترتيب عند تساوي الوقت: مشتريات ثم دفعات ثم مرتجعات ثم تصحيحات.
const TYPE_ORDER: Record<StatementEntryType, number> = {
  purchase: 0,
  payment: 1,
  return: 2,
  adjustment: 3,
};

export async function getCustomerStatement(
  db: Database,
  shopId: string,
  customerId: string,
  filter: StatementFilter = {},
): Promise<StatementView> {
  await requireLinkedCustomer(db, shopId, customerId);

  const purchaseRows = await db
    .select({
      id: purchases.id,
      shopSeq: purchases.shopSeq,
      occurredAt: purchases.occurredAt,
      itemsText: purchases.itemsText,
      totalAmount: purchases.totalAmount,
      status: purchases.status,
    })
    .from(purchases)
    .where(
      and(eq(purchases.shopId, shopId), eq(purchases.customerId, customerId)),
    );

  const paymentRows = await db
    .select({
      id: payments.id,
      shopSeq: payments.shopSeq,
      paidAt: payments.paidAt,
      amount: payments.amount,
      notes: payments.notes,
      purchaseId: payments.purchaseId,
    })
    .from(payments)
    .where(and(eq(payments.shopId, shopId), eq(payments.customerId, customerId)));

  const returnRows = await db
    .select({
      id: purchaseReturns.id,
      occurredAt: purchaseReturns.occurredAt,
      amount: purchaseReturns.amount,
      reason: purchaseReturns.reason,
      purchaseId: purchaseReturns.purchaseId,
    })
    .from(purchaseReturns)
    .where(
      and(
        eq(purchaseReturns.shopId, shopId),
        eq(purchaseReturns.customerId, customerId),
      ),
    );

  const adjustmentRows = await db
    .select({
      id: financialAdjustments.id,
      occurredAt: financialAdjustments.occurredAt,
      amount: financialAdjustments.amount,
      reason: financialAdjustments.reason,
      kind: financialAdjustments.kind,
      relatedPurchaseId: financialAdjustments.relatedPurchaseId,
    })
    .from(financialAdjustments)
    .where(
      and(
        eq(financialAdjustments.shopId, shopId),
        eq(financialAdjustments.customerId, customerId),
      ),
    );

  const allLines: RawLine[] = [];
  for (const p of purchaseRows) {
    allLines.push({
      id: p.id,
      type: "purchase",
      shopSeq: p.shopSeq,
      occurredAt: p.occurredAt,
      description: p.itemsText,
      signedAmount: p.status === "active" ? p.totalAmount : 0n,
      status: p.status,
      purchaseId: null,
      adjustmentKind: null,
    });
  }
  for (const p of paymentRows) {
    allLines.push({
      id: p.id,
      type: "payment",
      shopSeq: p.shopSeq,
      occurredAt: p.paidAt,
      description: p.notes && p.notes.length > 0 ? p.notes : "دفعة",
      signedAmount: -p.amount,
      status: "active",
      purchaseId: p.purchaseId,
      adjustmentKind: null,
    });
  }
  for (const r of returnRows) {
    allLines.push({
      id: r.id,
      type: "return",
      shopSeq: null,
      occurredAt: r.occurredAt,
      description: r.reason && r.reason.length > 0 ? r.reason : "مرتجع",
      signedAmount: -r.amount,
      status: "active",
      purchaseId: r.purchaseId,
      adjustmentKind: null,
    });
  }
  for (const a of adjustmentRows) {
    const label =
      a.kind === "cancellation"
        ? `إلغاء عملية${a.reason ? `: ${a.reason}` : ""}`
        : a.reason;
    allLines.push({
      id: a.id,
      type: "adjustment",
      shopSeq: null,
      occurredAt: a.occurredAt,
      description: label,
      signedAmount: a.amount,
      status: "active",
      purchaseId: a.relatedPurchaseId,
      adjustmentKind: a.kind,
    });
  }

  // ترتيب زمني تصاعدي (ثابت: عند التساوي نرتّب حسب النوع ثم المعرّف).
  allLines.sort((a, b) => {
    const t = a.occurredAt.getTime() - b.occurredAt.getTime();
    if (t !== 0) return t;
    const oa = TYPE_ORDER[a.type];
    const ob = TYPE_ORDER[b.type];
    if (oa !== ob) return oa - ob;
    return a.id.localeCompare(b.id);
  });

  // نطاق التصفية (للحساب الجاري، نحتاج ما قبل البداية لتأسيس الرصيد الافتتاحي).
  const fromTs = filter.from ? new Date(filter.from).getTime() : null;
  const toTs = filter.to ? new Date(filter.to).getTime() : null;
  const typeFilter = filter.type && filter.type !== "all" ? filter.type : null;

  let running = 0n;
  const entries: StatementEntry[] = [];
  for (const line of allLines) {
    running += line.signedAmount; // الرصيد الجاري عبر كل التاريخ
    const ts = line.occurredAt.getTime();
    const inRange =
      (fromTs === null || ts >= fromTs) && (toTs === null || ts <= toTs);
    const typeMatch = typeFilter === null || line.type === typeFilter;
    if (!inRange || !typeMatch) continue;

    entries.push({
      id: line.id,
      type: line.type,
      shopSeq: line.shopSeq === null ? null : line.shopSeq.toString(),
      occurredAt: line.occurredAt.toISOString(),
      description: line.description,
      effect: line.signedAmount.toString(),
      balanceAfter: running.toString(),
      status: line.status,
      purchaseId: line.purchaseId,
      adjustmentKind: line.adjustmentKind,
    });
  }

  // الإجماليات الكاملة (بلا تصفية) — تتوافق مع الرصيد المخزَّن.
  const breakdown = await customerBalanceBreakdown(db, shopId, customerId);

  return {
    customerId,
    totalPurchases: breakdown.totalPurchases.toString(),
    totalPayments: breakdown.totalPayments.toString(),
    totalReturns: breakdown.totalReturns.toString(),
    totalAdjustments: breakdown.totalAdjustments.toString(),
    balance: breakdown.balance.toString(),
    entries,
  };
}

// رصيد عميل مشتق (يُستخدم في موجز ملف العميل).
// = Σ مشتريات نشطة − Σ مدفوعات − Σ مرتجعات ± Σ تصحيحات.
export async function getCustomerBalance(
  db: Database,
  shopId: string,
  customerId: string,
): Promise<{
  totalPurchases: string;
  totalPayments: string;
  totalReturns: string;
  totalAdjustments: string;
  balance: string;
}> {
  await requireLinkedCustomer(db, shopId, customerId);
  const b = await customerBalanceBreakdown(db, shopId, customerId);
  return {
    totalPurchases: b.totalPurchases.toString(),
    totalPayments: b.totalPayments.toString(),
    totalReturns: b.totalReturns.toString(),
    totalAdjustments: b.totalAdjustments.toString(),
    balance: b.balance.toString(),
  };
}

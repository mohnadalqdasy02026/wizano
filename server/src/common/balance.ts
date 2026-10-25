// حساب رصيد العميل المشتق من السجلات المالية فقط (docs/01 §4.2 — D-09).
//
//   رصيد العميل = Σ المشتريات (النشطة)
//                − Σ المدفوعات
//                − Σ المرتجعات
//                ± Σ التصحيحات المالية (الموجب يزيد، السالب يخصم)
//
// لا يُخزَّن كقيمة يدوية؛ كل استدعائه يُعيد حساب الرصيد الحالي. يُستخدم في
// المشتريات والمدفوعات والمرتجعات والتصحيحات وكشف الحساب لضمان اتساق واحد.

import { and, eq, sql } from "drizzle-orm";
import type { Database } from "../db/index.js";
import {
  financialAdjustments,
  payments,
  purchaseReturns,
  purchases,
} from "../db/schema.js";

// نوع المنفّذ: قاعدة البيانات أو معاملة داخلها (نفس واجهة الاستعلام).
export type DbExecutor =
  | Database
  | Parameters<Parameters<Database["transaction"]>[0]>[0];

// يحسب رصيد العميل الحالي ضمن المحل (Σ مشتريات نشطة − مدفوعات − مرتجعات ± تصحيحات).
export async function computeCustomerBalance(
  db: DbExecutor,
  shopId: string,
  customerId: string,
): Promise<bigint> {
  const purchaseSum = await db
    .select({ total: sql<string>`coalesce(sum(${purchases.totalAmount}), 0)` })
    .from(purchases)
    .where(
      and(
        eq(purchases.shopId, shopId),
        eq(purchases.customerId, customerId),
        eq(purchases.status, "active"),
      ),
    );

  const paymentSum = await db
    .select({ total: sql<string>`coalesce(sum(${payments.amount}), 0)` })
    .from(payments)
    .where(and(eq(payments.shopId, shopId), eq(payments.customerId, customerId)));

  const returnSum = await db
    .select({ total: sql<string>`coalesce(sum(${purchaseReturns.amount}), 0)` })
    .from(purchaseReturns)
    .where(
      and(
        eq(purchaseReturns.shopId, shopId),
        eq(purchaseReturns.customerId, customerId),
      ),
    );

  const adjustmentSum = await db
    .select({
      total: sql<string>`coalesce(sum(${financialAdjustments.amount}), 0)`,
    })
    .from(financialAdjustments)
    .where(
      and(
        eq(financialAdjustments.shopId, shopId),
        eq(financialAdjustments.customerId, customerId),
      ),
    );

  const tp = BigInt(purchaseSum[0]?.total ?? "0");
  const tv = BigInt(paymentSum[0]?.total ?? "0");
  const tr = BigInt(returnSum[0]?.total ?? "0");
  const ta = BigInt(adjustmentSum[0]?.total ?? "0");
  return tp - tv - tr + ta;
}

// إجماليات مفصّلة (تُستخدم في كشف الحساب وموجز العميل).
export async function customerBalanceBreakdown(
  db: DbExecutor,
  shopId: string,
  customerId: string,
): Promise<{
  totalPurchases: bigint;
  totalPayments: bigint;
  totalReturns: bigint;
  totalAdjustments: bigint;
  balance: bigint;
}> {
  const purchaseSum = await db
    .select({ total: sql<string>`coalesce(sum(${purchases.totalAmount}), 0)` })
    .from(purchases)
    .where(
      and(
        eq(purchases.shopId, shopId),
        eq(purchases.customerId, customerId),
        eq(purchases.status, "active"),
      ),
    );
  const paymentSum = await db
    .select({ total: sql<string>`coalesce(sum(${payments.amount}), 0)` })
    .from(payments)
    .where(and(eq(payments.shopId, shopId), eq(payments.customerId, customerId)));
  const returnSum = await db
    .select({ total: sql<string>`coalesce(sum(${purchaseReturns.amount}), 0)` })
    .from(purchaseReturns)
    .where(
      and(
        eq(purchaseReturns.shopId, shopId),
        eq(purchaseReturns.customerId, customerId),
      ),
    );
  const adjustmentSum = await db
    .select({
      total: sql<string>`coalesce(sum(${financialAdjustments.amount}), 0)`,
    })
    .from(financialAdjustments)
    .where(
      and(
        eq(financialAdjustments.shopId, shopId),
        eq(financialAdjustments.customerId, customerId),
      ),
    );

  const tp = BigInt(purchaseSum[0]?.total ?? "0");
  const tv = BigInt(paymentSum[0]?.total ?? "0");
  const tr = BigInt(returnSum[0]?.total ?? "0");
  const ta = BigInt(adjustmentSum[0]?.total ?? "0");
  return {
    totalPurchases: tp,
    totalPayments: tv,
    totalReturns: tr,
    totalAdjustments: ta,
    balance: tp - tv - tr + ta,
  };
}

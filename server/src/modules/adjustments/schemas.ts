// تحقق مدخلات وحدة التصحيحات المالية والإلغاءات — Zod.

import { z } from "zod";

// التصحيح: مبلغ غير صفري (موجب يزيد الرصيد، سالب يخصم) + سبب إلزامي.
const adjustmentAmountSchema = z
  .int("المبلغ يجب أن يكون عددًا صحيحًا")
  .refine((v) => v !== 0, "المبلغ لا يكون صفرًا");

export const createAdjustmentBodySchema = z.object({
  id: z.uuid("معرّف التصحيح غير صالح").optional(),
  customerId: z.uuid("معرّف العميل غير صالح"),
  // اختياري: ربط التصحيح بعملية محددة (للتوثيق).
  relatedPurchaseId: z.uuid("معرّف العملية غير صالح").optional(),
  amount: adjustmentAmountSchema,
  reason: z
    .string()
    .trim()
    .min(1, "سبب التصحيح مطلوب")
    .max(2000, "السبب طويل جدًا"),
  occurredAt: z.iso.datetime({ offset: true }).optional(),
});

export const cancelPurchaseBodySchema = z.object({
  id: z.uuid("معرّف الإلغاء غير صالح").optional(),
  reason: z
    .string()
    .trim()
    .min(1, "سبب الإلغاء مطلوب")
    .max(2000, "السبب طويل جدًا"),
  occurredAt: z.iso.datetime({ offset: true }).optional(),
  // إصدار العملية المتوقع (قفل تفاؤلي) — اختياري؛ إن أُرسل وتعارض مع الخادم ⇒ 409.
  version: z
    .int("الإصدار يجب أن يكون عددًا صحيحًا")
    .positive("الإصدار يجب أن يكون موجبًا")
    .optional(),
});

export const shopIdParamSchema = z.object({
  shopId: z.uuid("معرّف المحل غير صالح"),
});

export const purchaseIdParamSchema = z.object({
  purchaseId: z.uuid("معرّف العملية غير صالح"),
});

export const adjustmentIdParamSchema = z.object({
  adjustmentId: z.uuid("معرّف التصحيح غير صالح"),
});

export const listAdjustmentsQuerySchema = z.object({
  customerId: z.uuid("معرّف العميل غير صالح").optional(),
});

export type CreateAdjustmentBody = z.infer<typeof createAdjustmentBodySchema>;
export type CancelPurchaseBody = z.infer<typeof cancelPurchaseBodySchema>;
export type ListAdjustmentsQuery = z.infer<typeof listAdjustmentsQuerySchema>;

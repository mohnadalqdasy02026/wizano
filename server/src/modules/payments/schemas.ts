// تحقق مدخلات وحدة المدفوعات — Zod.

import { z } from "zod";

// المبلغ: عدد صحيح موجب بالريال اليمني (bigint على مستوى القاعدة، والقيود amount > 0).
const amountSchema = z
  .int("المبلغ يجب أن يكون عددًا صحيحًا")
  .positive("المبلغ يجب أن يكون أكبر من صفر");

export const createPaymentBodySchema = z.object({
  // معرّف من العميل (UUIDv7) لأجل المزامنة/عدم الاتصال؛ يُولَّد خادميًا إن غاب.
  id: z.uuid("معرّف الدفعة غير صالح").optional(),
  customerId: z.uuid("معرّف العميل غير صالح"),
  // عملية اختيارية: دفعة مخصّصة لعملية شراء محددة (وإلا فهي دفعة عامة على الحساب).
  purchaseId: z.uuid("معرّف العملية غير صالح").optional(),
  amount: amountSchema,
  notes: z.string().trim().max(2000, "الملاحظات طويلة جدًا").optional(),
  // وقت الدفع (يُرسله التطبيق عند عدم الاتصال)؛ الافتراضي الآن خادميًا.
  paidAt: z.iso.datetime({ offset: true }).optional(),
});

export const paymentIdParamSchema = z.object({
  paymentId: z.uuid("معرّف الدفعة غير صالح"),
});

export const shopIdParamSchema = z.object({
  shopId: z.uuid("معرّف المحل غير صالح"),
});

export const listPaymentsQuerySchema = z.object({
  customerId: z.uuid("معرّف العميل غير صالح").optional(),
});

export type CreatePaymentBody = z.infer<typeof createPaymentBodySchema>;
export type ListPaymentsQuery = z.infer<typeof listPaymentsQuerySchema>;

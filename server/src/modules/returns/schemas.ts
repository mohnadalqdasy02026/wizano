// تحقق مدخلات وحدة المرتجعات — Zod.

import { z } from "zod";

const amountSchema = z
  .int("المبلغ يجب أن يكون عددًا صحيحًا")
  .positive("المبلغ يجب أن يكون أكبر من صفر");

export const createReturnBodySchema = z.object({
  // معرّف من العميل (UUIDv7) لأجل المزامنة/عدم الاتصال؛ يُولَّد خادميًا إن غاب.
  id: z.uuid("معرّف المرتجع غير صالح").optional(),
  // العملية الأصلية التي يرتبط بها المرتجع — إلزامية.
  purchaseId: z.uuid("معرّف العملية غير صالح"),
  amount: amountSchema,
  reason: z.string().trim().max(2000, "السبب طويل جدًا").optional(),
  // وقت المرتجع (يُرسله التطبيق عند عدم الاتصال)؛ الافتراضي الآن خادميًا.
  occurredAt: z.iso.datetime({ offset: true }).optional(),
});

export const shopIdParamSchema = z.object({
  shopId: z.uuid("معرّف المحل غير صالح"),
});

export const returnIdParamSchema = z.object({
  returnId: z.uuid("معرّف المرتجع غير صالح"),
});

export const listReturnsQuerySchema = z.object({
  customerId: z.uuid("معرّف العميل غير صالح").optional(),
});

export type CreateReturnBody = z.infer<typeof createReturnBodySchema>;
export type ListReturnsQuery = z.infer<typeof listReturnsQuerySchema>;

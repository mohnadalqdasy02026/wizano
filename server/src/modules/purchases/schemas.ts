// تحقق مدخلات وحدة المشتريات الآجلة — Zod.

import { z } from "zod";

// المبالغ: أعداد صحيحة غير سالبة بالريال اليمني (bigint على مستوى القاعدة).
const amountSchema = z
  .int("المبلغ يجب أن يكون عددًا صحيحًا")
  .nonnegative("المبلغ لا يكون سالبًا");

export const createPurchaseBodySchema = z
  .object({
    // معرّف من العميل (UUIDv7) لأجل المزامنة/عدم الاتصال؛ يُولَّد خادميًا إن غاب.
    id: z.uuid("معرّف العملية غير صالح").optional(),
    customerId: z.uuid("معرّف العميل غير صالح"),
    itemsText: z
      .string()
      .trim()
      .min(1, "تفاصيل الأصناف مطلوبة")
      .max(4000, "تفاصيل الأصناف طويلة جدًا"),
    totalAmount: amountSchema,
    paidAmount: amountSchema.default(0),
    notes: z.string().trim().max(2000, "الملاحظات طويلة جدًا").optional(),
    // وقت العملية (يُرسله التطبيق عند عدم الاتصال)؛ الافتراضي الآن خادميًا.
    occurredAt: z.iso.datetime({ offset: true }).optional(),
  })
  .refine((v) => v.paidAmount <= v.totalAmount, {
    message: "المبلغ المدفوع لا يتجاوز الإجمالي.",
    path: ["paidAmount"],
  });

export const purchaseIdParamSchema = z.object({
  purchaseId: z.uuid("معرّف العملية غير صالح"),
});

export const shopIdParamSchema = z.object({
  shopId: z.uuid("معرّف المحل غير صالح"),
});

export const listPurchasesQuerySchema = z.object({
  customerId: z.uuid("معرّف العميل غير صالح").optional(),
});

export type CreatePurchaseBody = z.infer<typeof createPurchaseBodySchema>;
export type ListPurchasesQuery = z.infer<typeof listPurchasesQuerySchema>;

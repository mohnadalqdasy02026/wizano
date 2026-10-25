// تحقق مدخلات وحدة كشف الحساب — Zod.

import { z } from "zod";

export const customerShopParamsSchema = z.object({
  shopId: z.uuid("معرّف المحل غير صالح"),
  customerId: z.uuid("معرّف العميل غير صالح"),
});

export const shopIdParamSchema = customerShopParamsSchema.pick({ shopId: true });

export const statementQuerySchema = z
  .object({
    // تصفية حسب النوع (اختياري).
    type: z
      .enum(["all", "purchase", "payment", "return", "adjustment"])
      .optional(),
    from: z.iso.datetime({ offset: true }).optional(),
    to: z.iso.datetime({ offset: true }).optional(),
  })
  .refine((v) => !v.from || !v.to || v.from <= v.to, {
    message: "نطاق التاريخ غير صالح.",
    path: ["from"],
  });

export type StatementQuery = z.infer<typeof statementQuerySchema>;

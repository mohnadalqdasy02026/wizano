// تحقق مدخلات وحدة المحلات — Zod.

import { z } from "zod";

// رمز عملة بأحرف كبيرة ثلاثية (ISO 4217)، الافتراضي YER.
const currencySchema = z
  .string()
  .trim()
  .toUpperCase()
  .regex(/^[A-Z]{3}$/, "رمز العملة يجب أن يكون ثلاثة أحرف (مثال: YER)");

// المنطقة الزمنية تُقبل بصيغة IANA صالحة (تُتحقق فعليًا عبر Intl) أو باسم
// محافظة عربي (مثل «صنعاء»). الاسم العربي قيمة عرضية لا تدخل في أي حساب مالي،
// لكنها الطريقة التي يتعرّف بها صاحب المحل على منطقته في التطبيق.
// تُرفض أي قيمة إنجليزية غير صالحة مثل «Not/AZone».
const arabicTimezonePattern = /^[\u0600-\u06FF\s—\-]+$/u;

const timezoneSchema = z
  .string()
  .trim()
  .min(1, "المنطقة الزمنية مطلوبة")
  .max(64, "المنطقة الزمنية طويلة جدًا")
  .refine(
    (tz) => {
      if (arabicTimezonePattern.test(tz)) return true;
      try {
        new Intl.DateTimeFormat("en-US", { timeZone: tz });
        return true;
      } catch {
        return false;
      }
    },
    {
      message:
        "المنطقة الزمنية غير صالحة (اسم محافظة عربي أو صيغة IANA مثل Asia/Aden)",
    },
  );

// تاريخ بصيغة YYYY-MM-DD.
const dateSchema = z
  .string()
  .regex(/^\d{4}-\d{2}-\d{2}$/, "التاريخ يجب أن يكون بصيغة YYYY-MM-DD")
  .refine((v) => !Number.isNaN(Date.parse(v)), "التاريخ غير صالح");

export const createShopBodySchema = z.object({
  name: z
    .string()
    .trim()
    .min(2, "اسم المحل قصير جدًا")
    .max(160, "اسم المحل طويل جدًا"),
  currency: currencySchema.default("YER"),
  timezone: timezoneSchema.default("Asia/Aden"),
  openingDate: dateSchema.optional(),
});

export const updateShopBodySchema = z
  .object({
    name: z
      .string()
      .trim()
      .min(2, "اسم المحل قصير جدًا")
      .max(160, "اسم المحل طويل جدًا")
      .optional(),
    currency: currencySchema.optional(),
    timezone: timezoneSchema.optional(),
    openingDate: dateSchema.nullable().optional(),
  })
  .refine((v) => Object.keys(v).length > 0, {
    message: "لا يوجد أي حقل للتعديل.",
  });

export const shopIdParamSchema = z.object({
  shopId: z.uuid("معرّف المحل غير صالح"),
});

export type CreateShopBody = z.infer<typeof createShopBodySchema>;
export type UpdateShopBody = z.infer<typeof updateShopBodySchema>;

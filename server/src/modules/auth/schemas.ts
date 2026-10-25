// التحقق من مدخلات المصادقة — Zod (docs/04-architecture.md §4).

import { z } from "zod";

// تطبيع الهاتف: أرقام فقط مع تقبل صيغ شائعة (يمن/دولي)؛ يُخزَّن موحّدًا.
const phoneSchema = z
  .string()
  .trim()
  .min(6, "رقم الهاتف قصير جدًا")
  .max(30, "رقم الهاتف طويل جدًا")
  .regex(/^[+]?[0-9][0-9\s-]*$/, "رقم الهاتف غير صالح");

const passwordSchema = z
  .string()
  .min(8, "كلمة المرور يجب أن تكون 8 أحرف على الأقل")
  .max(200, "كلمة المرور طويلة جدًا");

export const registerBodySchema = z
  .object({
    displayName: z
      .string()
      .trim()
      .min(2, "الاسم قصير جدًا")
      .max(120, "الاسم طويل جدًا"),
    email: z.email("البريد الإلكتروني غير صالح").trim().toLowerCase().optional(),
    phone: phoneSchema.optional(),
    password: passwordSchema,
  })
  .refine((v) => v.email || v.phone, {
    message: "يجب توفير البريد الإلكتروني أو رقم الهاتف",
    path: ["email"],
  });

export const loginBodySchema = z
  .object({
    email: z.email("البريد الإلكتروني غير صالح").trim().toLowerCase().optional(),
    phone: phoneSchema.optional(),
    password: z.string().min(1, "كلمة المرور مطلوبة").max(200),
  })
  .refine((v) => v.email || v.phone, {
    message: "يجب توفير البريد الإلكتروني أو رقم الهاتف",
    path: ["email"],
  });

export const refreshBodySchema = z.object({
  refreshToken: z.string().min(1, "رمز التجديد مطلوب"),
});

export const logoutBodySchema = z.object({
  refreshToken: z.string().min(1, "رمز التجديد مطلوب"),
});

export type RegisterBody = z.infer<typeof registerBodySchema>;
export type LoginBody = z.infer<typeof loginBodySchema>;
export type RefreshBody = z.infer<typeof refreshBodySchema>;
export type LogoutBody = z.infer<typeof logoutBodySchema>;

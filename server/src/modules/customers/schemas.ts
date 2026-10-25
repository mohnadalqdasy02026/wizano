// تحقق مدخلات وحدة العملاء — Zod.

import { z } from "zod";

const optionalPhone = z
  .string()
  .trim()
  .min(4, "رقم الهاتف قصير جدًا")
  .max(30, "رقم الهاتف طويل جدًا")
  .optional();

export const createCustomerBodySchema = z.object({
  // معرّف من العميل (UUIDv7) لأجل المزامنة/عدم الاتصال؛ يُولَّد خادميًا إن غاب.
  id: z.uuid("معرّف العميل غير صالح").optional(),
  displayName: z
    .string()
    .trim()
    .min(2, "اسم العميل قصير جدًا")
    .max(120, "اسم العميل طويل جدًا"),
  phone: optionalPhone,
  notes: z.string().trim().max(2000, "الملاحظات طويلة جدًا").optional(),
});

export const updateCustomerBodySchema = z
  .object({
    displayName: z
      .string()
      .trim()
      .min(2, "اسم العميل قصير جدًا")
      .max(120, "اسم العميل طويل جدًا")
      .optional(),
    phone: optionalPhone.nullable(),
    notes: z.string().trim().max(2000, "الملاحظات طويلة جدًا").nullable().optional(),
  })
  .refine((v) => Object.keys(v).length > 0, {
    message: "لا يوجد أي حقل للتعديل.",
  });

export const customerIdParamSchema = z.object({
  customerId: z.uuid("معرّف العميل غير صالح"),
});

export const shopIdParamSchema = z.object({
  shopId: z.uuid("معرّف المحل غير صالح"),
});

export const listCustomersQuerySchema = z.object({
  search: z.string().trim().max(120).optional(),
});

export const acceptInvitationBodySchema = z.object({
  code: z.string().trim().min(6).max(16),
});

export type CreateCustomerBody = z.infer<typeof createCustomerBodySchema>;
export type UpdateCustomerBody = z.infer<typeof updateCustomerBodySchema>;
export type ListCustomersQuery = z.infer<typeof listCustomersQuerySchema>;

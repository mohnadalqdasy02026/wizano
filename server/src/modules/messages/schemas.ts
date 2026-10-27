import { z } from "zod";

export const messageConversationParamsSchema = z.object({
  shopId: z.uuid("معرّف المحل غير صالح"),
  customerId: z.uuid("معرّف العميل غير صالح"),
});

export const messageShopParamsSchema = z.object({
  shopId: z.uuid("معرّف المحل غير صالح"),
});

export const sendMessageBodySchema = z.object({
  body: z
    .string()
    .trim()
    .min(1, "لا يمكن إرسال رسالة فارغة")
    .max(2000, "الرسالة طويلة جدًا"),
});

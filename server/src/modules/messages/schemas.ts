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
    .max(2000, "الرسالة طويلة جدًا")
    .optional(),
  audioBase64: z.string().max(1_500_000, "الرسالة الصوتية كبيرة جدًا").optional(),
  audioMimeType: z.string().max(80).optional(),
  audioDurationMs: z.number().int().min(1).max(30_000).optional(),
}).superRefine((value, ctx) => {
  if (!value.body && !value.audioBase64) {
    ctx.addIssue({ code: z.ZodIssueCode.custom, message: "لا يمكن إرسال رسالة فارغة" });
  }
  if (value.audioBase64 && (!value.audioMimeType || !value.audioDurationMs)) {
    ctx.addIssue({ code: z.ZodIssueCode.custom, message: "بيانات الصوت غير مكتملة" });
  }
});

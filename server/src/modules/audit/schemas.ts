// تحقق مدخلات وحدة سجل التدقيق — Zod.

import { z } from "zod";

export const shopIdParamSchema = z.object({
  shopId: z.uuid("معرّف المحل غير صالح"),
});

export const listAuditQuerySchema = z.object({
  entityType: z.string().trim().max(64).optional(),
  entityId: z.uuid("معرّف الكيان غير صالح").optional(),
  action: z.string().trim().max(64).optional(),
  limit: z.coerce.number().int().positive().max(200).optional(),
});

export type ListAuditQuery = z.infer<typeof listAuditQuerySchema>;

import { z } from "zod";

export const shopIdParamSchema = z.object({ shopId: z.string().uuid() });
export const objectionIdParamSchema = z.object({
  shopId: z.string().uuid(),
  objectionId: z.string().uuid(),
});

export const createObjectionBodySchema = z.object({
  customerId: z.string().uuid(),
  entityType: z.enum([
    "purchase",
    "payment",
    "purchase_return",
    "financial_adjustment",
  ]),
  entityId: z.string().uuid(),
  body: z.string().min(1).max(2000),
});

export const replyObjectionBodySchema = z.object({
  body: z.string().min(1).max(2000),
});

export const listObjectionsQuerySchema = z.object({
  status: z.enum(["open", "resolved", "rejected"]).optional(),
  customerId: z.string().uuid().optional(),
});

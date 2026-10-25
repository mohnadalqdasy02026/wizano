// مسارات المشتريات الآجلة — /api/v1/shops/:shopId/purchases/*
// كلها محمية بـ authenticate + requireShopMembership (عزل المحل R-06).

import type { FastifyInstance, FastifyReply, FastifyRequest } from "fastify";
import { db as defaultDb, type Database } from "../../db/index.js";
import { AppError } from "../../common/errors.js";
import { parseOrThrow } from "../../common/validation.js";
import {
  authenticate,
  requireOperationalRole,
  requirePermission,
  requireShopMembership,
} from "../../middleware/auth.js";
import {
  createPurchase,
  getPurchaseForShop,
  listShopPurchases,
} from "./service.js";
import {
  createPurchaseBodySchema,
  listPurchasesQuerySchema,
  purchaseIdParamSchema,
  shopIdParamSchema,
} from "./schemas.js";

export interface PurchasesDeps {
  db: Database;
}

export const defaultPurchasesDeps: PurchasesDeps = { db: defaultDb };

// وسيط مشترك: يستخرج shopId ويتحقق من الانتماء.
async function withMembership(
  req: FastifyRequest,
): Promise<{ shopId: string; userId: string; membership: Awaited<ReturnType<typeof requireShopMembership>> }> {
  const auth = req.auth;
  if (!auth) throw new AppError(401, "UNAUTHORIZED", "يجب تسجيل الدخول.");
  const { shopId } = parseOrThrow(shopIdParamSchema, req.params);
  const membership = await requireShopMembership(auth.userId, shopId);
  return { shopId, userId: auth.userId, membership };
}

export async function registerPurchaseRoutes(
  app: FastifyInstance,
  deps: PurchasesDeps = defaultPurchasesDeps,
): Promise<void> {
  // قائمة مشتريات المحل (+ تصفية اختيارية بالعميل).
  app.get(
    "/api/v1/shops/:shopId/purchases",
    { preHandler: authenticate },
    async (req: FastifyRequest) => {
      const { shopId, membership } = await withMembership(req);
      requireOperationalRole(membership);
      const query = parseOrThrow(listPurchasesQuerySchema, req.query ?? {});
      const items = await listShopPurchases(deps.db, shopId, query.customerId);
      return { data: { items } };
    },
  );

  // تسجيل عملية شراء آجلة (+ دفعة وقت الشراء إن وُجد مدفوع).
  app.post(
    "/api/v1/shops/:shopId/purchases",
    { preHandler: authenticate },
    async (req: FastifyRequest, reply: FastifyReply) => {
      const { shopId, userId, membership } = await withMembership(req);
      requirePermission(membership, "purchases.create");
      const body = parseOrThrow(createPurchaseBodySchema, req.body);
      const header = req.headers["idempotency-key"];
      const idempotencyKey =
        typeof header === "string" && header.trim().length > 0
          ? header.trim()
          : undefined;
      const purchase = await createPurchase(deps.db, shopId, userId, {
        ...body,
        idempotencyKey,
      });
      return reply.status(201).send({ data: purchase });
    },
  );

  // تفاصيل عملية (S15).
  app.get(
    "/api/v1/shops/:shopId/purchases/:purchaseId",
    { preHandler: authenticate },
    async (req: FastifyRequest) => {
      const { shopId, membership } = await withMembership(req);
      requireOperationalRole(membership);
      const { purchaseId } = parseOrThrow(purchaseIdParamSchema, req.params);
      const purchase = await getPurchaseForShop(deps.db, shopId, purchaseId);
      return { data: purchase };
    },
  );
}

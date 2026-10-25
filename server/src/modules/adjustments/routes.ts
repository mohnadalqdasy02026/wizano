// مسارات التصحيحات المالية والإلغاءات — /api/v1/shops/:shopId/adjustments/* و /purchases/:purchaseId/cancel
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
  cancelPurchase,
  createAdjustment,
  getAdjustmentForShop,
  listShopAdjustments,
} from "./service.js";
import {
  adjustmentIdParamSchema,
  cancelPurchaseBodySchema,
  createAdjustmentBodySchema,
  listAdjustmentsQuerySchema,
  purchaseIdParamSchema,
  shopIdParamSchema,
} from "./schemas.js";

export interface AdjustmentsDeps {
  db: Database;
}

export const defaultAdjustmentsDeps: AdjustmentsDeps = { db: defaultDb };

async function withMembership(
  req: FastifyRequest,
): Promise<{ shopId: string; userId: string; membership: Awaited<ReturnType<typeof requireShopMembership>> }> {
  const auth = req.auth;
  if (!auth) throw new AppError(401, "UNAUTHORIZED", "يجب تسجيل الدخول.");
  const { shopId } = parseOrThrow(shopIdParamSchema, req.params);
  const membership = await requireShopMembership(auth.userId, shopId);
  return { shopId, userId: auth.userId, membership };
}

function readIdempotencyKey(req: FastifyRequest): string | undefined {
  const header = req.headers["idempotency-key"];
  return typeof header === "string" && header.trim().length > 0
    ? header.trim()
    : undefined;
}

export async function registerAdjustmentRoutes(
  app: FastifyInstance,
  deps: AdjustmentsDeps = defaultAdjustmentsDeps,
): Promise<void> {
  // قائمة تصحيحات/إلغاءات المحل (+ تصفية اختيارية بالعميل).
  app.get(
    "/api/v1/shops/:shopId/adjustments",
    { preHandler: authenticate },
    async (req: FastifyRequest) => {
      const { shopId, membership } = await withMembership(req);
      requireOperationalRole(membership);
      const query = parseOrThrow(listAdjustmentsQuerySchema, req.query ?? {});
      const items = await listShopAdjustments(deps.db, shopId, query.customerId);
      return { data: { items } };
    },
  );

  // تسجيل تصحيح مالي (مبلغ + سبب إلزامي).
  app.post(
    "/api/v1/shops/:shopId/adjustments",
    { preHandler: authenticate },
    async (req: FastifyRequest, reply: FastifyReply) => {
      const { shopId, userId, membership } = await withMembership(req);
      requirePermission(membership, "adjustments.create");
      const body = parseOrThrow(createAdjustmentBodySchema, req.body);
      const created = await createAdjustment(deps.db, shopId, userId, {
        ...body,
        idempotencyKey: readIdempotencyKey(req),
      });
      return reply.status(201).send({ data: created });
    },
  );

  // تفاصيل تصحيح.
  app.get(
    "/api/v1/shops/:shopId/adjustments/:adjustmentId",
    { preHandler: authenticate },
    async (req: FastifyRequest) => {
      const { shopId, membership } = await withMembership(req);
      requireOperationalRole(membership);
      const { adjustmentId } = parseOrThrow(adjustmentIdParamSchema, req.params);
      const row = await getAdjustmentForShop(deps.db, shopId, adjustmentId);
      return { data: row };
    },
  );

  // إلغاء عملية شراء (قيد عكسي موثق — الأصل يبقى كما هو).
  app.post(
    "/api/v1/shops/:shopId/purchases/:purchaseId/cancel",
    { preHandler: authenticate },
    async (req: FastifyRequest, reply: FastifyReply) => {
      const { shopId, userId, membership } = await withMembership(req);
      requirePermission(membership, "purchases.cancel");
      const { purchaseId } = parseOrThrow(purchaseIdParamSchema, req.params);
      const body = parseOrThrow(cancelPurchaseBodySchema, req.body);
      const created = await cancelPurchase(deps.db, shopId, purchaseId, userId, {
        ...body,
        idempotencyKey: readIdempotencyKey(req),
      });
      return reply.status(201).send({ data: created });
    },
  );
}

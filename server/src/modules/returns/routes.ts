// مسارات المرتجعات — /api/v1/shops/:shopId/returns/*
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
import { createReturn, getReturnForShop, listShopReturns } from "./service.js";
import {
  createReturnBodySchema,
  listReturnsQuerySchema,
  returnIdParamSchema,
  shopIdParamSchema,
} from "./schemas.js";

export interface ReturnsDeps {
  db: Database;
}

export const defaultReturnsDeps: ReturnsDeps = { db: defaultDb };

async function withMembership(
  req: FastifyRequest,
): Promise<{ shopId: string; userId: string; membership: Awaited<ReturnType<typeof requireShopMembership>> }> {
  const auth = req.auth;
  if (!auth) throw new AppError(401, "UNAUTHORIZED", "يجب تسجيل الدخول.");
  const { shopId } = parseOrThrow(shopIdParamSchema, req.params);
  const membership = await requireShopMembership(auth.userId, shopId);
  return { shopId, userId: auth.userId, membership };
}

export async function registerReturnRoutes(
  app: FastifyInstance,
  deps: ReturnsDeps = defaultReturnsDeps,
): Promise<void> {
  // قائمة مرتجعات المحل (+ تصفية اختيارية بالعميل).
  app.get(
    "/api/v1/shops/:shopId/returns",
    { preHandler: authenticate },
    async (req: FastifyRequest) => {
      const { shopId, membership } = await withMembership(req);
      requireOperationalRole(membership);
      const query = parseOrThrow(listReturnsQuerySchema, req.query ?? {});
      const items = await listShopReturns(deps.db, shopId, query.customerId);
      return { data: { items } };
    },
  );

  // تسجيل مرتجع مرتبط بعملية.
  app.post(
    "/api/v1/shops/:shopId/returns",
    { preHandler: authenticate },
    async (req: FastifyRequest, reply: FastifyReply) => {
      const { shopId, userId, membership } = await withMembership(req);
      requirePermission(membership, "returns.create");
      const body = parseOrThrow(createReturnBodySchema, req.body);
      const header = req.headers["idempotency-key"];
      const idempotencyKey =
        typeof header === "string" && header.trim().length > 0
          ? header.trim()
          : undefined;
      const created = await createReturn(deps.db, shopId, userId, {
        ...body,
        idempotencyKey,
      });
      return reply.status(201).send({ data: created });
    },
  );

  // تفاصيل مرتجع.
  app.get(
    "/api/v1/shops/:shopId/returns/:returnId",
    { preHandler: authenticate },
    async (req: FastifyRequest) => {
      const { shopId, membership } = await withMembership(req);
      requireOperationalRole(membership);
      const { returnId } = parseOrThrow(returnIdParamSchema, req.params);
      const row = await getReturnForShop(deps.db, shopId, returnId);
      return { data: row };
    },
  );
}

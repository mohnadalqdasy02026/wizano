// مسارات المدفوعات — /api/v1/shops/:shopId/payments/*
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
  createPayment,
  getPaymentForShop,
  listShopPayments,
} from "./service.js";
import {
  createPaymentBodySchema,
  listPaymentsQuerySchema,
  paymentIdParamSchema,
  shopIdParamSchema,
} from "./schemas.js";

export interface PaymentsDeps {
  db: Database;
}

export const defaultPaymentsDeps: PaymentsDeps = { db: defaultDb };

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

export async function registerPaymentRoutes(
  app: FastifyInstance,
  deps: PaymentsDeps = defaultPaymentsDeps,
): Promise<void> {
  // قائمة دفعات المحل (+ تصفية اختيارية بالعميل).
  app.get(
    "/api/v1/shops/:shopId/payments",
    { preHandler: authenticate },
    async (req: FastifyRequest) => {
      const { shopId, membership } = await withMembership(req);
      requireOperationalRole(membership);
      const query = parseOrThrow(listPaymentsQuerySchema, req.query ?? {});
      const items = await listShopPayments(deps.db, shopId, query.customerId);
      return { data: { items } };
    },
  );

  // تسجيل دفعة (عامة على الحساب أو مرتبطة بعملية).
  app.post(
    "/api/v1/shops/:shopId/payments",
    { preHandler: authenticate },
    async (req: FastifyRequest, reply: FastifyReply) => {
      const { shopId, userId, membership } = await withMembership(req);
      requirePermission(membership, "payments.create");
      const body = parseOrThrow(createPaymentBodySchema, req.body);
      const header = req.headers["idempotency-key"];
      const idempotencyKey =
        typeof header === "string" && header.trim().length > 0
          ? header.trim()
          : undefined;
      const payment = await createPayment(deps.db, shopId, userId, {
        ...body,
        idempotencyKey,
      });
      return reply.status(201).send({ data: payment });
    },
  );

  // تفاصيل دفعة.
  app.get(
    "/api/v1/shops/:shopId/payments/:paymentId",
    { preHandler: authenticate },
    async (req: FastifyRequest) => {
      const { shopId, membership } = await withMembership(req);
      requireOperationalRole(membership);
      const { paymentId } = parseOrThrow(paymentIdParamSchema, req.params);
      const payment = await getPaymentForShop(deps.db, shopId, paymentId);
      return { data: payment };
    },
  );
}

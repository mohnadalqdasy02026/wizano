// مسارات العملاء — /api/v1/shops/:shopId/customers/*
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
  acceptInvitation,
  archiveCustomer,
  createCustomer,
  createInvitation,
  getCustomerForShop,
  listShopCustomers,
  updateCustomer,
} from "./service.js";
import {
  acceptInvitationBodySchema,
  createCustomerBodySchema,
  customerIdParamSchema,
  listCustomersQuerySchema,
  shopIdParamSchema,
  updateCustomerBodySchema,
} from "./schemas.js";

export interface CustomersDeps {
  db: Database;
}

export const defaultCustomersDeps: CustomersDeps = { db: defaultDb };

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

export async function registerCustomerRoutes(
  app: FastifyInstance,
  deps: CustomersDeps = defaultCustomersDeps,
): Promise<void> {
  app.post(
    "/api/v1/customer-invitations/accept",
    { preHandler: authenticate },
    async (req: FastifyRequest) => {
      const auth = req.auth;
      if (!auth) throw new AppError(401, "UNAUTHORIZED", "يجب تسجيل الدخول.");
      const body = parseOrThrow(acceptInvitationBodySchema, req.body);
      return { data: await acceptInvitation(deps.db, auth.userId, body.code) };
    },
  );

  // قائمة عملاء المحل (+ بحث اختياري).
  app.get(
    "/api/v1/shops/:shopId/customers",
    { preHandler: authenticate },
    async (req: FastifyRequest) => {
      const { shopId, membership } = await withMembership(req);
      requireOperationalRole(membership);
      const query = parseOrThrow(listCustomersQuerySchema, req.query ?? {});
      const items = await listShopCustomers(deps.db, shopId, query.search);
      return { data: { items } };
    },
  );

  // إنشاء عميل وربطه بالمحل.
  app.post(
    "/api/v1/shops/:shopId/customers",
    { preHandler: authenticate },
    async (req: FastifyRequest, reply: FastifyReply) => {
      const { shopId, membership } = await withMembership(req);
      requirePermission(membership, "customers.manage");
      const body = parseOrThrow(createCustomerBodySchema, req.body);
      const customer = await createCustomer(deps.db, shopId, body);
      return reply.status(201).send({ data: customer });
    },
  );

  // تفاصيل عميل.
  app.get(
    "/api/v1/shops/:shopId/customers/:customerId",
    { preHandler: authenticate },
    async (req: FastifyRequest) => {
      const { shopId, membership } = await withMembership(req);
      requireOperationalRole(membership);
      const { customerId } = parseOrThrow(customerIdParamSchema, req.params);
      const customer = await getCustomerForShop(deps.db, shopId, customerId);
      return { data: customer };
    },
  );

  // تعديل عميل.
  app.patch(
    "/api/v1/shops/:shopId/customers/:customerId",
    { preHandler: authenticate },
    async (req: FastifyRequest) => {
      const { shopId, membership } = await withMembership(req);
      requirePermission(membership, "customers.manage");
      const { customerId } = parseOrThrow(customerIdParamSchema, req.params);
      const body = parseOrThrow(updateCustomerBodySchema, req.body);
      const customer = await updateCustomer(deps.db, shopId, customerId, body);
      return { data: customer };
    },
  );

  // أرشفة عميل (حذف منطقي).
  app.delete(
    "/api/v1/shops/:shopId/customers/:customerId",
    { preHandler: authenticate },
    async (req: FastifyRequest, reply: FastifyReply) => {
      const { shopId, membership } = await withMembership(req);
      requirePermission(membership, "customers.manage");
      const { customerId } = parseOrThrow(customerIdParamSchema, req.params);
      await archiveCustomer(deps.db, shopId, customerId);
      return reply.status(204).send();
    },
  );

  // إنشاء رمز دعوة لربط العميل بالمحل (S12).
  app.post(
    "/api/v1/shops/:shopId/customers/:customerId/invitations",
    { preHandler: authenticate },
    async (req: FastifyRequest, reply: FastifyReply) => {
      const { shopId, userId, membership } = await withMembership(req);
      requirePermission(membership, "customers.manage");
      const { customerId } = parseOrThrow(customerIdParamSchema, req.params);
      const invite = await createInvitation(
        deps.db,
        shopId,
        customerId,
        userId,
      );
      return reply.status(201).send({ data: invite });
    },
  );
}


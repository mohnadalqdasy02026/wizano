import type { FastifyInstance, FastifyRequest } from "fastify";
import { db as defaultDb, type Database } from "../../db/index.js";
import { parseOrThrow } from "../../common/validation.js";
import {
  authenticate,
  requireOperationalRole,
  requireShopMembership,
} from "../../middleware/auth.js";
import { forbidden } from "../../common/errors.js";
import { getCustomerIdForUser } from "../customers/service.js";
import {
  shopIdParamSchema,
  objectionIdParamSchema,
  createObjectionBodySchema,
  replyObjectionBodySchema,
  listObjectionsQuerySchema,
} from "./schemas.js";
import {
  createObjection,
  listShopObjections,
  replyToObjection,
  resolveObjection,
} from "./service.js";

export interface ObjectionsDeps { db: Database; }
export const defaultObjectionsDeps: ObjectionsDeps = { db: defaultDb };

async function withMembership(req: FastifyRequest) {
  const auth = req.auth;
  if (!auth) throw new Error("UNAUTHORIZED");
  const { shopId } = parseOrThrow(shopIdParamSchema, req.params);
  const membership = await requireShopMembership(auth.userId, shopId);
  return { shopId, userId: auth.userId, membership };
}

export async function registerObjectionRoutes(app: FastifyInstance, deps: ObjectionsDeps = defaultObjectionsDeps): Promise<void> {
  app.get("/api/v1/shops/:shopId/objections", { preHandler: authenticate }, async (req) => {
    const { shopId, userId, membership } = await withMembership(req);
    const q = parseOrThrow(listObjectionsQuerySchema, req.query ?? {});
    const customerId = membership.role === "customer"
      ? await getCustomerIdForUser(deps.db, shopId, userId)
      : q.customerId;
    if (membership.role !== "customer") requireOperationalRole(membership);
    const items = await listShopObjections(deps.db, shopId, q.status, customerId);
    return { data: { items } };
  });

  app.post("/api/v1/shops/:shopId/objections", { preHandler: authenticate }, async (req, reply) => {
    const { shopId, userId, membership } = await withMembership(req);
    const body = parseOrThrow(createObjectionBodySchema, req.body);
    if (membership.role !== "customer") throw forbidden("إرسال الاعتراض متاح للعميل فقط.");
    const customerId = await getCustomerIdForUser(deps.db, shopId, userId);
    if (body.customerId !== customerId) throw forbidden("لا يمكنك إنشاء اعتراض لحساب عميل آخر.");
    const created = await createObjection(deps.db, shopId, body.customerId, body);
    return reply.status(201).send({ data: created });
  });

  app.post("/api/v1/shops/:shopId/objections/:objectionId/replies", { preHandler: authenticate }, async (req, reply) => {
    const { shopId, userId, membership } = await withMembership(req);
    requireOperationalRole(membership);
    const { objectionId } = parseOrThrow(objectionIdParamSchema, req.params);
    const body = parseOrThrow(replyObjectionBodySchema, req.body);
    await replyToObjection(deps.db, shopId, objectionId, userId, membership.role, body.body);
    return reply.status(201).send({ data: { ok: true } });
  });

  app.patch("/api/v1/shops/:shopId/objections/:objectionId/resolve", { preHandler: authenticate }, async (req) => {
    const { shopId, membership } = await withMembership(req);
    requireOperationalRole(membership);
    const { objectionId } = parseOrThrow(objectionIdParamSchema, req.params);
    await resolveObjection(deps.db, shopId, objectionId);
    return { data: { ok: true } };
  });
}

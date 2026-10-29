import type { FastifyInstance, FastifyRequest } from "fastify";
import { db as defaultDb, type Database } from "../../db/index.js";
import { AppError, forbidden } from "../../common/errors.js";
import { parseOrThrow } from "../../common/validation.js";
import {
  authenticate,
  requireOperationalRole,
  requireShopMembership,
} from "../../middleware/auth.js";
import { getCustomerIdForUser } from "../customers/service.js";
import {
  messageConversationParamsSchema,
  messageShopParamsSchema,
  sendMessageBodySchema,
} from "./schemas.js";
import { getCustomerUnreadCount, listConversationSummaries, listMessages, sendMessage, type SenderType } from "./service.js";

export interface MessagesDeps {
  db: Database;
}

export const defaultMessagesDeps: MessagesDeps = { db: defaultDb };

async function conversationActor(
  req: FastifyRequest,
  db: Database,
  shopId: string,
  customerId: string,
): Promise<{ userId: string; senderType: SenderType }> {
  const auth = req.auth;
  if (!auth) throw new AppError(401, "UNAUTHORIZED", "يجب تسجيل الدخول.");
  const membership = await requireShopMembership(auth.userId, shopId);
  if (membership.role === "customer") {
    const ownCustomerId = await getCustomerIdForUser(db, shopId, auth.userId);
    if (ownCustomerId !== customerId) {
      throw forbidden("لا يمكنك الوصول إلى محادثة عميل آخر.");
    }
    return { userId: auth.userId, senderType: "customer" };
  }
  requireOperationalRole(membership);
  return { userId: auth.userId, senderType: "shop" };
}

export async function registerMessageRoutes(
  app: FastifyInstance,
  deps: MessagesDeps = defaultMessagesDeps,
): Promise<void> {
  app.get(
    "/api/v1/shops/:shopId/message-summaries",
    { preHandler: authenticate },
    async (req: FastifyRequest) => {
      const auth = req.auth;
      if (!auth) throw new AppError(401, "UNAUTHORIZED", "يجب تسجيل الدخول.");
      const { shopId } = parseOrThrow(messageShopParamsSchema, req.params);
      const membership = await requireShopMembership(auth.userId, shopId);
      requireOperationalRole(membership);
      return { data: { items: await listConversationSummaries(deps.db, shopId) } };
    },
  );

  app.get(
    "/api/v1/shops/:shopId/customers/:customerId/messages",
    { preHandler: authenticate },
    async (req: FastifyRequest) => {
      const { shopId, customerId } = parseOrThrow(
        messageConversationParamsSchema,
        req.params,
      );
      const actor = await conversationActor(req, deps.db, shopId, customerId);
      return {
        data: { items: await listMessages(deps.db, shopId, customerId, actor.senderType) },
      };
    },
  );

  app.post(
    "/api/v1/shops/:shopId/customers/:customerId/messages",
    { preHandler: authenticate },
    async (req: FastifyRequest) => {
      const { shopId, customerId } = parseOrThrow(
        messageConversationParamsSchema,
        req.params,
      );
      const actor = await conversationActor(req, deps.db, shopId, customerId);
      const body = parseOrThrow(sendMessageBodySchema, req.body);
      return {
        data: await sendMessage(deps.db, {
          shopId,
          customerId,
          senderUserId: actor.userId,
          senderType: actor.senderType,
          body: body.body,
          audioBase64: body.audioBase64,
          audioMimeType: body.audioMimeType,
          audioDurationMs: body.audioDurationMs,
        }),
      };
    },
  );

  app.get(
    "/api/v1/shops/:shopId/my-message-summary",
    { preHandler: authenticate },
    async (req: FastifyRequest) => {
      const auth = req.auth;
      if (!auth) throw new AppError(401, "UNAUTHORIZED", "يجب تسجيل الدخول.");
      const { shopId } = parseOrThrow(messageShopParamsSchema, req.params);
      const membership = await requireShopMembership(auth.userId, shopId);
      if (membership.role !== "customer") throw forbidden("هذا المسار مخصص لحساب العميل.");
      const customerId = await getCustomerIdForUser(deps.db, shopId, auth.userId);
      return { data: { unreadCount: await getCustomerUnreadCount(deps.db, shopId, customerId) } };
    },
  );

  app.get(
    "/api/v1/shops/:shopId/my-messages",
    { preHandler: authenticate },
    async (req: FastifyRequest) => {
      const auth = req.auth;
      if (!auth) throw new AppError(401, "UNAUTHORIZED", "يجب تسجيل الدخول.");
      const { shopId } = parseOrThrow(messageShopParamsSchema, req.params);
      const membership = await requireShopMembership(auth.userId, shopId);
      if (membership.role !== "customer") {
        throw forbidden("هذا المسار مخصص لحساب العميل.");
      }
      const customerId = await getCustomerIdForUser(deps.db, shopId, auth.userId);
      return {
        data: { items: await listMessages(deps.db, shopId, customerId, "customer") },
      };
    },
  );

  app.post(
    "/api/v1/shops/:shopId/my-messages",
    { preHandler: authenticate },
    async (req: FastifyRequest) => {
      const auth = req.auth;
      if (!auth) throw new AppError(401, "UNAUTHORIZED", "يجب تسجيل الدخول.");
      const { shopId } = parseOrThrow(messageShopParamsSchema, req.params);
      const membership = await requireShopMembership(auth.userId, shopId);
      if (membership.role !== "customer") {
        throw forbidden("هذا المسار مخصص لحساب العميل.");
      }
      const customerId = await getCustomerIdForUser(deps.db, shopId, auth.userId);
      const body = parseOrThrow(sendMessageBodySchema, req.body);
      return {
        data: await sendMessage(deps.db, {
          shopId,
          customerId,
          senderUserId: auth.userId,
          senderType: "customer",
          body: body.body,
          audioBase64: body.audioBase64,
          audioMimeType: body.audioMimeType,
          audioDurationMs: body.audioDurationMs,
        }),
      };
    },
  );
}

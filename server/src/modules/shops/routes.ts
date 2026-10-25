// مسارات المحلات — /api/v1/shops/*
// محمية بـ authenticate؛ الإنشاء لأي مستخدم مُصادَق؛ الجلب للعضو؛ التعديل للمالك فقط.

import type { FastifyInstance, FastifyReply, FastifyRequest } from "fastify";
import { db as defaultDb, type Database } from "../../db/index.js";
import { AppError, forbidden } from "../../common/errors.js";
import { parseOrThrow } from "../../common/validation.js";
import {
  authenticate,
  requireShopMembership,
} from "../../middleware/auth.js";
import {
  createShop,
  getShopById,
  listUserShops,
  updateShop,
} from "./service.js";
import {
  createShopBodySchema,
  shopIdParamSchema,
  updateShopBodySchema,
} from "./schemas.js";

export interface ShopsDeps {
  db: Database;
}

export const defaultShopsDeps: ShopsDeps = { db: defaultDb };

export async function registerShopRoutes(
  app: FastifyInstance,
  deps: ShopsDeps = defaultShopsDeps,
): Promise<void> {
  // إنشاء محل — أي مستخدم مُصادَق يصبح مالكه.
  app.post(
    "/api/v1/shops",
    { preHandler: authenticate },
    async (req: FastifyRequest, reply: FastifyReply) => {
      const auth = req.auth;
      if (!auth) throw new AppError(401, "UNAUTHORIZED", "يجب تسجيل الدخول.");
      const body = parseOrThrow(createShopBodySchema, req.body);
      const shop = await createShop(deps.db, auth.userId, body);
      return reply.status(201).send({ data: shop });
    },
  );

  // محلات المستخدم.
  app.get(
    "/api/v1/shops",
    { preHandler: authenticate },
    async (req: FastifyRequest) => {
      const auth = req.auth;
      if (!auth) throw new AppError(401, "UNAUTHORIZED", "يجب تسجيل الدخول.");
      const items = await listUserShops(deps.db, auth.userId);
      return { data: { items } };
    },
  );

  // تفاصيل محل — للعضو فقط.
  app.get(
    "/api/v1/shops/:shopId",
    { preHandler: authenticate },
    async (req: FastifyRequest) => {
      const auth = req.auth;
      if (!auth) throw new AppError(401, "UNAUTHORIZED", "يجب تسجيل الدخول.");
      const { shopId } = parseOrThrow(shopIdParamSchema, req.params);
      await requireShopMembership(auth.userId, shopId);
      const shop = await getShopById(deps.db, shopId);
      return { data: shop };
    },
  );

  // تعديل محل — للمالك فقط.
  app.patch(
    "/api/v1/shops/:shopId",
    { preHandler: authenticate },
    async (req: FastifyRequest) => {
      const auth = req.auth;
      if (!auth) throw new AppError(401, "UNAUTHORIZED", "يجب تسجيل الدخول.");
      const { shopId } = parseOrThrow(shopIdParamSchema, req.params);
      const membership = await requireShopMembership(auth.userId, shopId);
      if (membership.role !== "owner") {
        throw forbidden("تعديل بيانات المحل متاح للمالك فقط.");
      }
      const body = parseOrThrow(updateShopBodySchema, req.body);
      const shop = await updateShop(deps.db, shopId, body);
      return { data: shop };
    },
  );
}

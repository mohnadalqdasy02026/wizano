// مسارات سجل التدقيق — /api/v1/shops/:shopId/audit-logs
// محمية بـ authenticate + requireShopMembership (عزل المحل R-06).

import type { FastifyInstance, FastifyRequest } from "fastify";
import { db as defaultDb, type Database } from "../../db/index.js";
import { AppError } from "../../common/errors.js";
import { parseOrThrow } from "../../common/validation.js";
import {
  authenticate,
  requireOwner,
  requireShopMembership,
} from "../../middleware/auth.js";
import { listShopAuditLogs } from "./service.js";
import { listAuditQuerySchema, shopIdParamSchema } from "./schemas.js";

export interface AuditDeps {
  db: Database;
}

export const defaultAuditDeps: AuditDeps = { db: defaultDb };

export async function registerAuditRoutes(
  app: FastifyInstance,
  deps: AuditDeps = defaultAuditDeps,
): Promise<void> {
  app.get(
    "/api/v1/shops/:shopId/audit-logs",
    { preHandler: authenticate },
    async (req: FastifyRequest) => {
      const auth = req.auth;
      if (!auth) throw new AppError(401, "UNAUTHORIZED", "يجب تسجيل الدخول.");
      const { shopId } = parseOrThrow(shopIdParamSchema, req.params);
      const membership = await requireShopMembership(auth.userId, shopId);
      requireOwner(membership);
      const query = parseOrThrow(listAuditQuerySchema, req.query ?? {});
      const items = await listShopAuditLogs(deps.db, shopId, query);
      return { data: { items } };
    },
  );
}

// مسارات كشف الحساب — /api/v1/shops/:shopId/customers/:customerId/statement
// محمية بـ authenticate + requireShopMembership (عزل المحل R-06).

import type { FastifyInstance, FastifyRequest } from "fastify";
import { db as defaultDb, type Database } from "../../db/index.js";
import { AppError } from "../../common/errors.js";
import { parseOrThrow } from "../../common/validation.js";
import {
  authenticate,
  requireOperationalRole,
  requireShopMembership,
} from "../../middleware/auth.js";
import { getCustomerIdForUser } from "../customers/service.js";
import { getCustomerStatement } from "./service.js";
import {
  customerShopParamsSchema,
  shopIdParamSchema,
  statementQuerySchema,
} from "./schemas.js";

export interface StatementsDeps {
  db: Database;
}

export const defaultStatementsDeps: StatementsDeps = { db: defaultDb };

export async function registerStatementRoutes(
  app: FastifyInstance,
  deps: StatementsDeps = defaultStatementsDeps,
): Promise<void> {
  // كشف حساب عميل: العمليات زمنيًا + الرصيد الجاري + الإجماليات.
  app.get(
    "/api/v1/shops/:shopId/customers/:customerId/statement",
    { preHandler: authenticate },
    async (req: FastifyRequest) => {
      const auth = req.auth;
      if (!auth) throw new AppError(401, "UNAUTHORIZED", "يجب تسجيل الدخول.");
      const { shopId, customerId } = parseOrThrow(
        customerShopParamsSchema,
        req.params,
      );
      const membership = await requireShopMembership(auth.userId, shopId);
      requireOperationalRole(membership);
      const query = parseOrThrow(statementQuerySchema, req.query ?? {});
      const statement = await getCustomerStatement(deps.db, shopId, customerId, {
        type: query.type,
        from: query.from,
        to: query.to,
      });
      return { data: statement };
    },
  );

  app.get(
    "/api/v1/shops/:shopId/my-statement",
    { preHandler: authenticate },
    async (req: FastifyRequest) => {
      const auth = req.auth;
      if (!auth) throw new AppError(401, "UNAUTHORIZED", "يجب تسجيل الدخول.");
      const { shopId } = parseOrThrow(shopIdParamSchema, req.params);
      const membership = await requireShopMembership(auth.userId, shopId);
      if (membership.role !== "customer") {
        throw new AppError(403, "FORBIDDEN", "هذا المسار مخصص لحساب العميل.");
      }
      const customerId = await getCustomerIdForUser(deps.db, shopId, auth.userId);
      const query = parseOrThrow(statementQuerySchema, req.query ?? {});
      const statement = await getCustomerStatement(deps.db, shopId, customerId, query);
      return { data: statement };
    },
  );
}

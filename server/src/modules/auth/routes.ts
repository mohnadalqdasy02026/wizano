// مسارات المصادقة — /api/v1/auth/*
// الشكل: { data, meta? } في النجاح؛ الأخطاء عبر setErrorHandler الموحّد.

import type { FastifyInstance, FastifyReply, FastifyRequest } from "fastify";
import { db as defaultDb, type Database } from "../../db/index.js";
import { AppError } from "../../common/errors.js";
import { parseOrThrow } from "../../common/validation.js";
import { authenticate } from "../../middleware/auth.js";
import { env } from "../../config/index.js";
import {
  getCurrentUser,
  loginUser,
  logoutUser,
  refreshTokens,
  registerUser,
} from "./service.js";
import {
  loginBodySchema,
  logoutBodySchema,
  refreshBodySchema,
  registerBodySchema,
} from "./schemas.js";

export interface AuthDeps {
  db: Database;
}

export const defaultAuthDeps: AuthDeps = { db: defaultDb };

export async function registerAuthRoutes(
  app: FastifyInstance,
  deps: AuthDeps = defaultAuthDeps,
): Promise<void> {
  // حدّ أضيق لمحاولات المصادقة (مقاومة تخمين كلمة المرور — R-08).
  const authRateLimit = {
    rateLimit: {
      max: env.AUTH_RATE_LIMIT_MAX,
      timeWindow: env.AUTH_RATE_LIMIT_WINDOW,
    },
  };

  app.post(
    "/api/v1/auth/register",
    { config: authRateLimit },
    async (req: FastifyRequest, reply: FastifyReply) => {
      const body = parseOrThrow(registerBodySchema, req.body);
      const result = await registerUser(deps.db, body);
      return reply.status(201).send({ data: result });
    },
  );

  app.post(
    "/api/v1/auth/login",
    { config: authRateLimit },
    async (req: FastifyRequest) => {
      const body = parseOrThrow(loginBodySchema, req.body);
      const result = await loginUser(deps.db, body);
      return { data: result };
    },
  );

  app.post(
    "/api/v1/auth/refresh",
    { config: authRateLimit },
    async (req: FastifyRequest) => {
      const body = parseOrThrow(refreshBodySchema, req.body);
      const result = await refreshTokens(deps.db, body.refreshToken);
      return { data: result };
    },
  );

  app.post(
    "/api/v1/auth/logout",
    async (req: FastifyRequest, reply: FastifyReply) => {
      const body = parseOrThrow(logoutBodySchema, req.body);
      await logoutUser(deps.db, body.refreshToken);
      return reply.status(204).send();
    },
  );

  app.get(
    "/api/v1/me",
    { preHandler: authenticate },
    async (req: FastifyRequest) => {
      const auth = req.auth;
      if (!auth) throw new AppError(401, "UNAUTHORIZED", "يجب تسجيل الدخول.");
      const result = await getCurrentUser(deps.db, auth.userId);
      return { data: result };
    },
  );
}

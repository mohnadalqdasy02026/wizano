import Fastify, { type FastifyError, type FastifyInstance } from "fastify";
import cors from "@fastify/cors";
import helmet from "@fastify/helmet";
import rateLimit from "@fastify/rate-limit";
import { corsOrigins, env } from "./config/index.js";
import {
  registerHealthRoutes,
  type HealthDeps,
} from "./modules/health/routes.js";
import {
  registerAuthRoutes,
  type AuthDeps,
} from "./modules/auth/routes.js";
import {
  registerShopRoutes,
  type ShopsDeps,
} from "./modules/shops/routes.js";
import {
  registerCustomerRoutes,
  type CustomersDeps,
} from "./modules/customers/routes.js";
import {
  registerPurchaseRoutes,
  type PurchasesDeps,
} from "./modules/purchases/routes.js";
import {
  registerPaymentRoutes,
  type PaymentsDeps,
} from "./modules/payments/routes.js";
import {
  registerStatementRoutes,
  type StatementsDeps,
} from "./modules/statements/routes.js";
import {
  registerReturnRoutes,
  type ReturnsDeps,
} from "./modules/returns/routes.js";
import {
  registerAdjustmentRoutes,
  type AdjustmentsDeps,
} from "./modules/adjustments/routes.js";
import {
  registerAuditRoutes,
  type AuditDeps,
} from "./modules/audit/routes.js";
import {
  registerObjectionRoutes,
  type ObjectionsDeps,
} from "./modules/objections/routes.js";
import { AppError } from "./common/errors.js";
import {
  registerNotificationRoutes,
  type NotificationsDeps,
} from "./modules/notifications/routes.js";

export interface BuildAppOptions {
  healthDeps?: HealthDeps;
  authDeps?: AuthDeps;
  shopsDeps?: ShopsDeps;
  customersDeps?: CustomersDeps;
  purchasesDeps?: PurchasesDeps;
  paymentsDeps?: PaymentsDeps;
  statementsDeps?: StatementsDeps;
  returnsDeps?: ReturnsDeps;
  adjustmentsDeps?: AdjustmentsDeps;
  auditDeps?: AuditDeps;
  objectionsDeps?: ObjectionsDeps;
  notificationsDeps?: NotificationsDeps;
}

export async function buildApp(opts: BuildAppOptions = {}): Promise<FastifyInstance> {
  const app = Fastify({
    logger:
      env.NODE_ENV === "test"
        ? false
        : {
            level: env.LOG_LEVEL,
            ...(env.NODE_ENV === "development"
              ? { transport: { target: "pino-pretty" } }
              : {}),
          },
    trustProxy: env.TRUST_PROXY,
  });

  await app.register(helmet);
  await app.register(cors, {
    origin: corsOrigins.length > 0 ? corsOrigins : false,
  });
  await app.register(rateLimit, {
    max: env.RATE_LIMIT_GLOBAL_MAX,
    timeWindow: env.RATE_LIMIT_GLOBAL_WINDOW,
  });

  // حالة حدّية شائعة: طلب DELETE (أو غيره) بترويسة JSON وبلا جسم.
  // نعتبرها جسمًا فارغًا (undefined) بدل رفضها بـ 400.
  app.addContentTypeParser(
    "application/json",
    { parseAs: "string" },
    (_req, body, done) => {
      const raw = (body as string).trim();
      if (raw.length === 0) return done(null, undefined);
      try {
        done(null, JSON.parse(raw));
      } catch (err) {
        (err as Error & { statusCode?: number }).statusCode = 400;
        done(err as Error, undefined);
      }
    },
  );

  await registerHealthRoutes(app, opts.healthDeps);
  await registerAuthRoutes(app, opts.authDeps);
  await registerShopRoutes(app, opts.shopsDeps);
  await registerCustomerRoutes(app, opts.customersDeps);
  await registerPurchaseRoutes(app, opts.purchasesDeps);
  await registerPaymentRoutes(app, opts.paymentsDeps);
  await registerStatementRoutes(app, opts.statementsDeps);
  await registerReturnRoutes(app, opts.returnsDeps);
  await registerAdjustmentRoutes(app, opts.adjustmentsDeps);
  await registerAuditRoutes(app, opts.auditDeps);
  await registerObjectionRoutes(app, opts.objectionsDeps);
  await registerNotificationRoutes(app, opts.notificationsDeps);

  app.setNotFoundHandler((_req, reply) => {
    reply.status(404).send({
      error: {
        code: "NOT_FOUND",
        message_ar: "المسار غير موجود.",
      },
    });
  });

  app.setErrorHandler((error: FastifyError, _req, reply) => {
    // خطأ تطبيقي معروف → شكل موحّد وحالة محدّدة.
    if (error instanceof AppError) {
      reply.status(error.statusCode).send({
        error: {
          code: error.code,
          message_ar: error.messageAr,
          ...(error.details !== undefined ? { details: error.details } : {}),
        },
      });
      return;
    }

    const statusCode =
      error.statusCode && error.statusCode >= 400 ? error.statusCode : 500;
    if (statusCode >= 500) {
      app.log.error(error);
    }
    reply.status(statusCode).send({
      error: {
        code: statusCode >= 500 ? "INTERNAL_ERROR" : "BAD_REQUEST",
        message_ar:
          statusCode >= 500
            ? "حدث خطأ غير متوقع في الخادم."
            : "الطلب غير صالح.",
      },
    });
  });

  return app;
}

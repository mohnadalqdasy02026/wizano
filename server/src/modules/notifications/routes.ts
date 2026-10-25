import type { FastifyInstance, FastifyRequest } from "fastify";
import { db as defaultDb, type Database } from "../../db/index.js";
import { parseOrThrow } from "../../common/validation.js";
import { authenticate } from "../../middleware/auth.js";
import { notificationIdParamSchema } from "./schemas.js";
import { listNotifications, markRead } from "./service.js";

export interface NotificationsDeps { db: Database; }
export const defaultNotificationsDeps: NotificationsDeps = { db: defaultDb };

export async function registerNotificationRoutes(app: FastifyInstance, deps: NotificationsDeps = defaultNotificationsDeps): Promise<void> {
  app.get("/api/v1/notifications", { preHandler: authenticate }, async (req) => {
    const auth = (req as any).auth;
    const items = await listNotifications(deps.db, auth.userId);
    return { data: { items } };
  });
  app.patch("/api/v1/notifications/:notificationId/read", { preHandler: authenticate }, async (req) => {
    const auth = (req as any).auth;
    const { notificationId } = parseOrThrow(notificationIdParamSchema, req.params);
    await markRead(deps.db, auth.userId, notificationId);
    return { data: { ok: true } };
  });
}
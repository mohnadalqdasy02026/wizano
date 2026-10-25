import { and, eq } from "drizzle-orm";
import type { Database } from "../../db/index.js";
import { notifications } from "../../db/schema.js";
import { notFound } from "../../common/errors.js";

export async function listNotifications(db: Database, userId: string) {
  const rows = await db.select().from(notifications).where(eq(notifications.userId, userId));
  return rows.map((r) => ({
    id: r.id,
    shopId: r.shopId,
    type: r.type,
    title: r.title,
    body: r.body,
    readAt: r.readAt ? r.readAt.toISOString() : null,
    createdAt: r.createdAt.toISOString(),
  }));
}

export async function markRead(db: Database, userId: string, notificationId: string) {
  const rows = await db
    .update(notifications)
    .set({ readAt: new Date() })
    .where(and(eq(notifications.id, notificationId), eq(notifications.userId, userId)))
    .returning();
  if (rows.length === 0) throw notFound("الإشعار غير موجود.");
  return { ok: true };
}
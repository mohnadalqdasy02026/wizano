// منطق وحدة سجل التدقيق — قراءة فقط (الكتابة تتم داخل الوحدات المالية).
// السجل غير قابل للتعديل/الحذف (trigger في migrations-custom.sql).

import { and, desc, eq } from "drizzle-orm";
import type { Database } from "../../db/index.js";
import { auditLogs } from "../../db/schema.js";

export interface AuditEntryView {
  id: string;
  shopId: string;
  actorUserId: string | null;
  action: string;
  entityType: string;
  entityId: string;
  before: unknown;
  after: unknown;
  createdAt: string;
}

export interface AuditFilter {
  entityType?: string;
  entityId?: string;
  action?: string;
  limit?: number;
}

export async function listShopAuditLogs(
  db: Database,
  shopId: string,
  filter: AuditFilter = {},
): Promise<AuditEntryView[]> {
  const conditions = [eq(auditLogs.shopId, shopId)];
  if (filter.entityType) {
    conditions.push(eq(auditLogs.entityType, filter.entityType));
  }
  if (filter.entityId) conditions.push(eq(auditLogs.entityId, filter.entityId));
  if (filter.action) conditions.push(eq(auditLogs.action, filter.action));

  const rows = await db
    .select()
    .from(auditLogs)
    .where(and(...conditions))
    .orderBy(desc(auditLogs.createdAt))
    .limit(filter.limit ?? 100);

  return rows.map((row) => ({
    id: row.id,
    shopId: row.shopId,
    actorUserId: row.actorUserId,
    action: row.action,
    entityType: row.entityType,
    entityId: row.entityId,
    before: row.before,
    after: row.after,
    createdAt: row.createdAt.toISOString(),
  }));
}

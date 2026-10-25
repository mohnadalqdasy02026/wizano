// سجل التدقيق (docs/01 §4.3، R-06 #6): كل إجراء مالي موثَّق بالمستخدم/الوقت/قبل-بعد.
// الجدول غير قابل للتعديل/الحذف (trigger في migrations-custom.sql)؛ هنا نكتب فقط.

import type { Database } from "../db/index.js";
import { auditLogs } from "../db/schema.js";

export type DbExecutor =
  | Database
  | Parameters<Parameters<Database["transaction"]>[0]>[0];

export interface AuditInput {
  shopId: string;
  actorUserId: string;
  action: string; // مثل: purchase.return, adjustment.create, purchase.cancel
  entityType: string; // purchase | payment | purchase_return | financial_adjustment
  entityId: string;
  before?: unknown;
  after?: unknown;
}

// يسجّل إجراءً في سجل التدقيق ضمن نفس المعاملة (لضمان الذرّية مع العملية المالية).
export async function writeAuditLog(
  db: DbExecutor,
  input: AuditInput,
): Promise<void> {
  await db.insert(auditLogs).values({
    shopId: input.shopId,
    actorUserId: input.actorUserId,
    action: input.action,
    entityType: input.entityType,
    entityId: input.entityId,
    before: input.before ?? null,
    after: input.after ?? null,
  });
}

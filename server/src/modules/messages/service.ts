import { and, asc, eq, isNull } from "drizzle-orm";
import type { Database } from "../../db/index.js";
import {
  customerMessages,
  customerShopLinks,
} from "../../db/schema.js";
import { notFound } from "../../common/errors.js";

export type SenderType = "shop" | "customer";

export interface MessageView {
  id: string;
  body: string;
  senderType: SenderType;
  createdAt: string;
  readAt: string | null;
}

async function requireLinkedCustomer(
  db: Database,
  shopId: string,
  customerId: string,
): Promise<void> {
  const rows = await db
    .select({ id: customerShopLinks.id })
    .from(customerShopLinks)
    .where(
      and(
        eq(customerShopLinks.shopId, shopId),
        eq(customerShopLinks.customerId, customerId),
        eq(customerShopLinks.status, "active"),
      ),
    )
    .limit(1);
  if (rows.length === 0) throw notFound("العميل غير مرتبط بهذا المحل.");
}

function toMessageView(row: typeof customerMessages.$inferSelect): MessageView {
  return {
    id: row.id,
    body: row.body,
    senderType: row.senderType,
    createdAt: row.createdAt.toISOString(),
    readAt: row.readAt?.toISOString() ?? null,
  };
}

export async function listMessages(
  db: Database,
  shopId: string,
  customerId: string,
  readerType: SenderType,
): Promise<MessageView[]> {
  await requireLinkedCustomer(db, shopId, customerId);

  const senderTypeToMarkRead: SenderType =
    readerType === "customer" ? "shop" : "customer";
  await db
    .update(customerMessages)
    .set({ readAt: new Date() })
    .where(
      and(
        eq(customerMessages.shopId, shopId),
        eq(customerMessages.customerId, customerId),
        eq(customerMessages.senderType, senderTypeToMarkRead),
        isNull(customerMessages.readAt),
      ),
    );

  const rows = await db
    .select()
    .from(customerMessages)
    .where(
      and(
        eq(customerMessages.shopId, shopId),
        eq(customerMessages.customerId, customerId),
      ),
    )
    .orderBy(asc(customerMessages.createdAt));
  return rows.map(toMessageView);
}

export async function sendMessage(
  db: Database,
  input: {
    shopId: string;
    customerId: string;
    senderUserId: string;
    senderType: SenderType;
    body: string;
  },
): Promise<MessageView> {
  await requireLinkedCustomer(db, input.shopId, input.customerId);
  const inserted = await db
    .insert(customerMessages)
    .values(input)
    .returning();
  const row = inserted[0];
  if (!row) throw new Error("تعذر إرسال الرسالة.");
  return toMessageView(row);
}

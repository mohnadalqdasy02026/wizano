import { and, asc, desc, eq, isNull } from "drizzle-orm";
import type { Database } from "../../db/index.js";
import {
  customerMessages,
  customerShopLinks,
  customers,
} from "../../db/schema.js";
import { notFound } from "../../common/errors.js";

export type SenderType = "shop" | "customer";

export interface MessageView {
  id: string;
  body: string | null;
  senderType: SenderType;
  createdAt: string;
  readAt: string | null;
  audioBase64: string | null;
  audioMimeType: string | null;
  audioDurationMs: number | null;
}

export interface ConversationSummary {
  customerId: string;
  customerName: string;
  lastBody: string | null;
  lastIsAudio: boolean;
  lastCreatedAt: string;
  unreadCount: number;
}

export async function getCustomerUnreadCount(
  db: Database,
  shopId: string,
  customerId: string,
): Promise<number> {
  await requireLinkedCustomer(db, shopId, customerId);
  const rows = await db
    .select({ id: customerMessages.id })
    .from(customerMessages)
    .where(and(
      eq(customerMessages.shopId, shopId),
      eq(customerMessages.customerId, customerId),
      eq(customerMessages.senderType, "shop"),
      isNull(customerMessages.readAt),
    ));
  return rows.length;
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
    audioBase64: row.audioBase64,
    audioMimeType: row.audioMimeType,
    audioDurationMs: row.audioDurationMs,
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

/// ملخصات المحادثات لصاحب المحل. لا يعلّم الرسائل كمقروءة؛ يحدث ذلك فقط عند
/// فتح محادثة العميل نفسها، مثل واتساب.
export async function listConversationSummaries(
  db: Database,
  shopId: string,
): Promise<ConversationSummary[]> {
  const rows = await db
    .select({
      customerId: customerMessages.customerId,
      customerName: customers.displayName,
      body: customerMessages.body,
      hasAudio: customerMessages.audioBase64,
      senderType: customerMessages.senderType,
      readAt: customerMessages.readAt,
      createdAt: customerMessages.createdAt,
    })
    .from(customerMessages)
    .innerJoin(customers, eq(customers.id, customerMessages.customerId))
    .where(eq(customerMessages.shopId, shopId))
    .orderBy(desc(customerMessages.createdAt));

  const byCustomer = new Map<string, ConversationSummary>();
  for (const row of rows) {
    const previous = byCustomer.get(row.customerId);
    if (!previous) {
      byCustomer.set(row.customerId, {
        customerId: row.customerId,
        customerName: row.customerName,
        lastBody: row.body,
        lastIsAudio: row.hasAudio != null,
        lastCreatedAt: row.createdAt.toISOString(),
        unreadCount: row.senderType === "customer" && row.readAt == null ? 1 : 0,
      });
    } else if (row.senderType === "customer" && row.readAt == null) {
      previous.unreadCount++;
    }
  }
  return [...byCustomer.values()];
}

export async function sendMessage(
  db: Database,
  input: {
    shopId: string;
    customerId: string;
    senderUserId: string;
    senderType: SenderType;
    body?: string;
    audioBase64?: string;
    audioMimeType?: string;
    audioDurationMs?: number;
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

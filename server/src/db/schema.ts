// مخطط قاعدة البيانات المركزية — المرحلة 3.
// الاستماع: docs/01-requirements.md §8 + docs/05-decisions-risks.md (D-07..D-10).
// قواعد عامة:
// - المعرّفات: UUID يولّده العميل (UUIDv7) للجداول المالية (D-07)، وgen_random_uuid() لجداول الخادم.
// - المبالغ: bigint بالريال اليمني الكامل (لا وحدة فرعية عملية لليمني) — القيود مفروضة على مستوى القاعدة.
// - العمليات المالية المعتمدة لا تُحذف فيزيائيًا؛ الإلغاء = قيد عكسي (D-10) — ومنع الحذف/التعديل
//   على سجل التدقيق مفروض عبر trigger في migrations-custom.sql.
// - «الرصيد بعد العملية» قيمة مشتقة تُحفظ لقابلية التحقق وإعادة الحساب (D-09).

import { sql } from "drizzle-orm";
import {
  bigint,
  check,
  date,
  integer,
  jsonb,
  pgEnum,
  pgTable,
  text,
  timestamp,
  uniqueIndex,
  uuid,
  varchar,
  index,
} from "drizzle-orm/pg-core";

// ---------------------------------------------------------------------------
// أنواع موحدة (enums)
// ---------------------------------------------------------------------------

export const userRoleEnum = pgEnum("user_role", [
  "owner",
  "staff",
  "customer",
  "system_admin",
]);

export const userStatusEnum = pgEnum("user_status", ["active", "disabled"]);

export const shopStatusEnum = pgEnum("shop_status", [
  "active",
  "suspended",
  "closed",
]);

export const memberStatusEnum = pgEnum("member_status", ["active", "removed"]);

export const linkStatusEnum = pgEnum("link_status", ["active", "removed"]);

export const invitationStatusEnum = pgEnum("invitation_status", [
  "pending",
  "accepted",
  "expired",
  "revoked",
]);

export const purchaseStatusEnum = pgEnum("purchase_status", [
  "active",
  "cancelled",
]);

export const syncOpStatusEnum = pgEnum("sync_op_status", [
  "accepted",
  "rejected",
  "conflict",
]);

export const objectionStatusEnum = pgEnum("objection_status", [
  "open",
  "under_review",
  "resolved",
  "rejected",
]);

export const objectionEntityTypeEnum = pgEnum("objection_entity_type", [
  "purchase",
  "payment",
  "purchase_return",
  "financial_adjustment",
]);

export const adjustmentKindEnum = pgEnum("adjustment_kind", [
  "correction",
  "cancellation",
]);

export const notificationTypeEnum = pgEnum("notification_type", [
  "info",
  "warning",
  "objection",
  "sync",
]);

export const deviceStatusEnum = pgEnum("device_status", ["active", "revoked"]);

// ---------------------------------------------------------------------------
// الحقول المشتركة (قوالب)
// ---------------------------------------------------------------------------

const id = () =>
  uuid("id").primaryKey(); // من العميل UUIDv7 (مالية) أو gen_random_uuid (خادم)

const createdAt = () =>
  timestamp("created_at", { withTimezone: true }).defaultNow().notNull();

const updatedAt = () =>
  timestamp("updated_at", { withTimezone: true })
    .defaultNow()
    .notNull()
    .$onUpdate(() => new Date());

const shopId = () =>
  uuid("shop_id")
    .notNull()
    .references(() => shops.id, { onDelete: "restrict" });

const customerId = () =>
  uuid("customer_id")
    .notNull()
    .references(() => customers.id, { onDelete: "restrict" });

const money = (name: string) =>
  bigint(name, { mode: "bigint" }).notNull();

// ---------------------------------------------------------------------------
// 1. المستخدمون والحسابات
// ---------------------------------------------------------------------------

export const users = pgTable(
  "users",
  {
    id: id().defaultRandom(),
    email: text("email"), // يُخزَّن بأحرف صغيرة؛ NULL مسموح (هاتف فقط)
    phone: varchar("phone", { length: 30 }),
    passwordHash: text("password_hash").notNull(), // argon2id — لا يُعرض ولا يُسجَّل
    displayName: varchar("display_name", { length: 120 }).notNull(),
    status: userStatusEnum("status").default("active").notNull(),
    locale: varchar("locale", { length: 10 }).default("ar").notNull(),
    lastLoginAt: timestamp("last_login_at", { withTimezone: true }),
    createdAt: createdAt(),
    updatedAt: updatedAt(),
  },
  (t) => [
    uniqueIndex("users_email_unique")
      .on(t.email)
      .where(sql`${t.email} is not null`),
    uniqueIndex("users_phone_unique")
      .on(t.phone)
      .where(sql`${t.phone} is not null`),
  ],
);

// ---------------------------------------------------------------------------
// 2. المحلات
// ---------------------------------------------------------------------------

export const shops = pgTable(
  "shops",
  {
    id: id().defaultRandom(),
    name: varchar("name", { length: 160 }).notNull(),
    currency: varchar("currency", { length: 3 }).default("YER").notNull(),
    timezone: varchar("timezone", { length: 64 }).default("Asia/Aden").notNull(),
    openingDate: date("opening_date"),
    status: shopStatusEnum("status").default("active").notNull(),
    createdBy: uuid("created_by").references(() => users.id, {
      onDelete: "set null",
    }),
    createdAt: createdAt(),
    updatedAt: updatedAt(),
  },
  (t) => [index("shops_status_idx").on(t.status)],
);

// ---------------------------------------------------------------------------
// 3. أعضاء المحل (مالك/موظف/عميل) + مفاتيح صلاحيات الموظف
// ---------------------------------------------------------------------------

export const shopMembers = pgTable(
  "shop_members",
  {
    id: id().defaultRandom(),
    shopId: shopId(),
    userId: uuid("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "restrict" }),
    role: userRoleEnum("role").notNull(),
    // مفاتيح صلاحية دور staff: purchases.create, payments.create, returns.create...
    permissionKeys: text("permission_keys").array().default(sql`'{}'`).notNull(),
    status: memberStatusEnum("status").default("active").notNull(),
    createdAt: createdAt(),
    updatedAt: updatedAt(),
  },
  (t) => [
    uniqueIndex("shop_members_shop_user_active_unique")
      .on(t.shopId, t.userId)
      .where(sql`${t.status} = 'active'`),
    index("shop_members_user_idx").on(t.userId),
  ],
);

// ---------------------------------------------------------------------------
// 4. عدّادات المحل (أرقام العمليات ضمن نطاق المحل)
// ---------------------------------------------------------------------------

export const shopCounters = pgTable(
  "shop_counters",
  {
    id: id().defaultRandom(),
    shopId: shopId(),
    kind: varchar("kind", { length: 32 }).notNull(), // purchase | payment | return | adjustment
    lastValue: bigint("last_value", { mode: "bigint" }).default(sql`0`).notNull(),
    createdAt: createdAt(),
    updatedAt: updatedAt(),
  },
  (t) => [uniqueIndex("shop_counters_shop_kind_unique").on(t.shopId, t.kind)],
);

// ---------------------------------------------------------------------------
// 5. العملاء (مستقل عن المحل) + ربط المحلات + الدعوات
// ---------------------------------------------------------------------------

export const customers = pgTable(
  "customers",
  {
    id: id(), // يولّده تطبيق المالك UUIDv7
    displayName: varchar("display_name", { length: 120 }).notNull(),
    phone: varchar("phone", { length: 30 }),
    notes: text("notes"),
    archivedAt: timestamp("archived_at", { withTimezone: true }),
    version: integer("version").default(1).notNull(), // قفل تفاؤلي (تعارضات المزامنة)
    createdAt: createdAt(),
    updatedAt: updatedAt(),
  },
  (t) => [
    index("customers_phone_idx").on(t.phone),
    index("customers_name_idx").on(t.displayName),
  ],
);

export const customerShopLinks = pgTable(
  "customer_shop_links",
  {
    id: id().defaultRandom(),
    customerId: customerId(),
    shopId: shopId(),
    status: linkStatusEnum("status").default("active").notNull(),
    createdAt: createdAt(),
    updatedAt: updatedAt(),
  },
  (t) => [
    uniqueIndex("customer_shop_links_customer_shop_active_unique")
      .on(t.customerId, t.shopId)
      .where(sql`${t.status} = 'active'`),
    index("customer_shop_links_shop_idx").on(t.shopId),
  ],
);

// ربط حساب تسجيل الدخول بسجل العميل. لا يُستنتج العميل من مدخلات الهاتف أو البريد.
export const customerUserLinks = pgTable(
  "customer_user_links",
  {
    id: id().defaultRandom(),
    customerId: customerId(),
    userId: uuid("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    createdAt: createdAt(),
  },
  (t) => [
    uniqueIndex("customer_user_links_customer_user_unique").on(
      t.customerId,
      t.userId,
    ),
    index("customer_user_links_user_idx").on(t.userId),
  ],
);

export const invitations = pgTable(
  "invitations",
  {
    id: id().defaultRandom(),
    shopId: shopId(),
    customerId: customerId(),
    code: varchar("code", { length: 16 }).notNull(), // رمز قصير للربط (يُحسم شكله في المرحلة 7)
    status: invitationStatusEnum("status").default("pending").notNull(),
    expiresAt: timestamp("expires_at", { withTimezone: true }).notNull(),
    acceptedAt: timestamp("accepted_at", { withTimezone: true }),
    createdBy: uuid("created_by").references(() => users.id, {
      onDelete: "set null",
    }),
    createdAt: createdAt(),
    updatedAt: updatedAt(),
  },
  (t) => [
    uniqueIndex("invitations_code_unique").on(t.code),
    index("invitations_shop_status_idx").on(t.shopId, t.status),
  ],
);

// ---------------------------------------------------------------------------
// 6. المشتريات الآجلة (الجدول المالي الأساسي)
//    القيود: إجمالي ≥ 0، مدفوع ≥ 0، مدفوع ≤ إجمالي، متبقي = إجمالي − مدفوع
// ---------------------------------------------------------------------------

export const purchases = pgTable(
  "purchases",
  {
    id: id(), // UUIDv7 من العميل (D-07)
    shopId: shopId(),
    customerId: customerId(),
    shopSeq: bigint("shop_seq", { mode: "bigint" }).notNull(), // رقم واضح ضمن المحل
    occurredAt: timestamp("occurred_at", { withTimezone: true }).notNull(),
    itemsText: text("items_text").notNull(), // تفاصيل الأصناف نصًا (لا استخراج أسعار منه)
    totalAmount: money("total_amount"), // إجمالي يدوي دائمًا
    paidAmount: money("paid_amount"), // المدفوع وقت الشراء (يُقيَّد كدفعة مستقلة)
    remainingAmount: money("remaining_amount"), // مشتق: إجمالي − مدفوع
    notes: text("notes"),
    status: purchaseStatusEnum("status").default("active").notNull(),
    statusReason: text("status_reason"), // سبب الإلغاء/الرفض إن وُجد
    cancelledAt: timestamp("cancelled_at", { withTimezone: true }),
    balanceAfter: bigint("balance_after", { mode: "bigint" }), // رصيد العميل بعد هذه العملية (D-09)
    version: integer("version").default(1).notNull(), // قفل تفاؤلي
    createdBy: uuid("created_by").references(() => users.id, {
      onDelete: "set null",
    }),
    createdAt: createdAt(),
    updatedAt: updatedAt(),
  },
  (t) => [
    uniqueIndex("purchases_shop_seq_unique").on(t.shopId, t.shopSeq),
    index("purchases_shop_created_idx").on(t.shopId, t.createdAt),
    index("purchases_shop_customer_idx").on(t.shopId, t.customerId, t.occurredAt),
    index("purchases_shop_status_idx").on(t.shopId, t.status),
    // القيود المالية الإلزامية (§4.1): إجمالي ≥ 0، مدفوع ≥ 0، مدفوع ≤ إجمالي، متبقي = إجمالي − مدفوع
    check(
      "purchases_total_non_negative",
      sql`${t.totalAmount} >= 0`,
    ),
    check(
      "purchases_paid_non_negative",
      sql`${t.paidAmount} >= 0`,
    ),
    check(
      "purchases_paid_lte_total",
      sql`${t.paidAmount} <= ${t.totalAmount}`,
    ),
    check(
      "purchases_remaining_computed",
      sql`${t.remainingAmount} = ${t.totalAmount} - ${t.paidAmount}`,
    ),
  ],
);

// ---------------------------------------------------------------------------
// 7. المدفوعات (ترتبط بالعميل والمحل + عملية شراء اختياريًا)
//    المبلغ المدفوع وقت الشراء يُسجَّل دفعة مستقلة هنا حتى لا يُحسب مرتين.
// ---------------------------------------------------------------------------

export const payments = pgTable(
  "payments",
  {
    id: id(), // UUIDv7 من العميل
    shopId: shopId(),
    customerId: customerId(),
    purchaseId: uuid("purchase_id").references(() => purchases.id, {
      onDelete: "restrict",
    }), // اختياري: دفعة مرتبطة بعملية محددة
    amount: money("amount"), // > 0
    paidAt: timestamp("paid_at", { withTimezone: true }).notNull(),
    shopSeq: bigint("shop_seq", { mode: "bigint" }),
    notes: text("notes"),
    balanceAfter: bigint("balance_after", { mode: "bigint" }),
    version: integer("version").default(1).notNull(),
    createdBy: uuid("created_by").references(() => users.id, {
      onDelete: "set null",
    }),
    createdAt: createdAt(),
    updatedAt: updatedAt(),
  },
  (t) => [
    index("payments_shop_created_idx").on(t.shopId, t.createdAt),
    index("payments_shop_customer_idx").on(t.shopId, t.customerId, t.paidAt),
    index("payments_purchase_idx").on(t.purchaseId),
    check("payments_amount_positive", sql`${t.amount} > 0`),
  ],
);

// ---------------------------------------------------------------------------
// 8. المرتجعات (قيد يخصم من رصيد العميل، مرتبط بالعملية الأصلية)
// ---------------------------------------------------------------------------

export const purchaseReturns = pgTable(
  "purchase_returns",
  {
    id: id(),
    shopId: shopId(),
    customerId: customerId(),
    purchaseId: uuid("purchase_id")
      .notNull()
      .references(() => purchases.id, { onDelete: "restrict" }),
    amount: money("amount"), // > 0
    reason: text("reason"),
    occurredAt: timestamp("occurred_at", { withTimezone: true }).notNull(),
    balanceAfter: bigint("balance_after", { mode: "bigint" }),
    version: integer("version").default(1).notNull(),
    createdBy: uuid("created_by").references(() => users.id, {
      onDelete: "set null",
    }),
    createdAt: createdAt(),
    updatedAt: updatedAt(),
  },
  (t) => [
    index("returns_shop_purchase_idx").on(t.shopId, t.purchaseId),
    index("returns_shop_created_idx").on(t.shopId, t.createdAt),
    index("returns_shop_customer_idx").on(t.shopId, t.customerId, t.occurredAt),
    check("returns_amount_positive", sql`${t.amount} > 0`),
  ],
);

// ---------------------------------------------------------------------------
// 9. التصحيحات المالية والإلغاءات (سبب إلزامي؛ موجب/سالب)
// ---------------------------------------------------------------------------

export const financialAdjustments = pgTable(
  "financial_adjustments",
  {
    id: id(),
    shopId: shopId(),
    customerId: customerId(),
    relatedPurchaseId: uuid("related_purchase_id").references(() => purchases.id, {
      onDelete: "restrict",
    }),
    kind: adjustmentKindEnum("kind").default("correction").notNull(),
    amount: money("amount"), // <> 0 — موجب يزيد الرصيد، سالب يخصم
    reason: text("reason").notNull(), // إلزامي مبرَّر
    occurredAt: timestamp("occurred_at", { withTimezone: true }).notNull(),
    balanceAfter: bigint("balance_after", { mode: "bigint" }),
    version: integer("version").default(1).notNull(),
    createdBy: uuid("created_by").references(() => users.id, {
      onDelete: "set null",
    }),
    createdAt: createdAt(),
    updatedAt: updatedAt(),
  },
  (t) => [
    index("adjustments_shop_customer_idx").on(t.shopId, t.customerId, t.occurredAt),
    index("adjustments_shop_created_idx").on(t.shopId, t.createdAt),
    index("adjustments_purchase_idx").on(t.relatedPurchaseId),
    check("adjustments_amount_non_zero", sql`${t.amount} <> 0`),
  ],
);

// ---------------------------------------------------------------------------
// 10. الاعتراضات وردودها
// ---------------------------------------------------------------------------

export const objections = pgTable(
  "objections",
  {
    id: id(),
    shopId: shopId(),
    customerId: customerId(),
    entityType: objectionEntityTypeEnum("entity_type").notNull(),
    entityId: uuid("entity_id").notNull(),
    body: text("body").notNull(),
    status: objectionStatusEnum("status").default("open").notNull(),
    resolvedAt: timestamp("resolved_at", { withTimezone: true }),
    createdAt: createdAt(),
    updatedAt: updatedAt(),
  },
  (t) => [
    index("objections_shop_status_idx").on(t.shopId, t.status),
    index("objections_customer_idx").on(t.shopId, t.customerId, t.createdAt),
    index("objections_entity_idx").on(t.entityType, t.entityId),
  ],
);

export const objectionReplies = pgTable(
  "objection_replies",
  {
    id: id().defaultRandom(),
    objectionId: uuid("objection_id")
      .notNull()
      .references(() => objections.id, { onDelete: "restrict" }),
    authorUserId: uuid("author_user_id").references(() => users.id, {
      onDelete: "set null",
    }),
    authorRole: userRoleEnum("author_role").notNull(), // owner | staff | customer
    body: text("body").notNull(),
    createdAt: createdAt(),
  },
  (t) => [index("objection_replies_objection_idx").on(t.objectionId, t.createdAt)],
);

// ---------------------------------------------------------------------------
// 11. الإشعارات الداخلية (ليست مصدرًا للرصيد)
// ---------------------------------------------------------------------------

export const notifications = pgTable(
  "notifications",
  {
    id: id().defaultRandom(),
    shopId: shopId(),
    userId: uuid("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    type: notificationTypeEnum("type").default("info").notNull(),
    title: varchar("title", { length: 160 }).notNull(),
    body: text("body"),
    readAt: timestamp("read_at", { withTimezone: true }),
    createdAt: createdAt(),
  },
  (t) => [
    index("notifications_user_read_idx").on(t.userId, t.readAt),
    index("notifications_shop_created_idx").on(t.shopId, t.createdAt),
  ],
);

// ---------------------------------------------------------------------------
// 12. سجل التدقيق (غير قابل للتعديل/الحذف — trigger في migrations-custom.sql)
// ---------------------------------------------------------------------------

export const auditLogs = pgTable(
  "audit_logs",
  {
    id: id().defaultRandom(),
    shopId: shopId(),
    actorUserId: uuid("actor_user_id").references(() => users.id, {
      onDelete: "set null",
    }),
    action: varchar("action", { length: 64 }).notNull(), // purchase.create, payment.update...
    entityType: varchar("entity_type", { length: 64 }).notNull(),
    entityId: uuid("entity_id").notNull(),
    before: jsonb("before"), // الحالة قبل التعديل (بلا كلمات مرور أو رموز)
    after: jsonb("after"),
    createdAt: createdAt(),
  },
  (t) => [
    index("audit_logs_shop_created_idx").on(t.shopId, t.createdAt),
    index("audit_logs_entity_idx").on(t.entityType, t.entityId),
    index("audit_logs_actor_idx").on(t.actorUserId),
  ],
);

// ---------------------------------------------------------------------------
// 13. سجل المزامنة ومفاتيح idempotency (منع التكرار — R-07)
// ---------------------------------------------------------------------------

export const syncOperations = pgTable(
  "sync_operations",
  {
    id: id().defaultRandom(),
    shopId: shopId(),
    actorUserId: uuid("actor_user_id").references(() => users.id, {
      onDelete: "set null",
    }),
    deviceId: uuid("device_id"), // لا قيد FK ليبقى السجل عند إلغاء الجهاز
    idempotencyKey: varchar("idempotency_key", { length: 128 }).notNull(),
    operationType: varchar("operation_type", { length: 32 }).notNull(), // push
    entityType: varchar("entity_type", { length: 64 }).notNull(),
    entityId: uuid("entity_id").notNull(), // معرّف العميل الثابت (UUIDv7)
    status: syncOpStatusEnum("status").notNull(),
    reason: text("reason"), // سبب الرفض/التعارض
    requestPayload: jsonb("request_payload"),
    createdAt: createdAt(),
  },
  (t) => [
    uniqueIndex("sync_operations_shop_idempotency_unique").on(
      t.shopId,
      t.idempotencyKey,
    ),
    index("sync_operations_shop_created_idx").on(t.shopId, t.createdAt),
    index("sync_operations_entity_idx").on(t.entityType, t.entityId),
  ],
);

// ---------------------------------------------------------------------------
// 14. الأجهزة المسجلة (لإبطال الجلسات — R-08)
// ---------------------------------------------------------------------------

export const deviceRegistrations = pgTable(
  "device_registrations",
  {
    id: id().defaultRandom(),
    userId: uuid("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    shopId: shopId(),
    deviceName: varchar("device_name", { length: 120 }),
    platform: varchar("platform", { length: 32 }), // android | web...
    status: deviceStatusEnum("status").default("active").notNull(),
    lastSeenAt: timestamp("last_seen_at", { withTimezone: true }),
    revokedAt: timestamp("revoked_at", { withTimezone: true }),
    createdAt: createdAt(),
    updatedAt: updatedAt(),
  },
  (t) => [
    index("device_registrations_user_idx").on(t.userId, t.shopId),
  ],
);

// ---------------------------------------------------------------------------
// 15. رموز التجديد (الجلسات) — تدوير + قائمة سوداء (D-05، R-08)
//    لا يُخزَّن الرمز نفسه بل بصمته (SHA-256)؛ عند التدوير يُبطَل القديم.
// ---------------------------------------------------------------------------

export const refreshTokens = pgTable(
  "refresh_tokens",
  {
    id: id().defaultRandom(),
    userId: uuid("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    deviceId: uuid("device_id").references(() => deviceRegistrations.id, {
      onDelete: "set null",
    }),
    tokenHash: varchar("token_hash", { length: 64 }).notNull(), // SHA-256 hex
    // السلسلة التي ينتمي إليها الرمز؛ عند إعادة الاستخدام نُبطِل السلسلة كاملة
    familyId: uuid("family_id").notNull(),
    expiresAt: timestamp("expires_at", { withTimezone: true }).notNull(),
    revokedAt: timestamp("revoked_at", { withTimezone: true }),
    // الرمز الذي حلّ محلّ هذا عند التدوير (لتتبع السلسلة)
    replacedByTokenId: uuid("replaced_by_token_id"),
    createdAt: createdAt(),
  },
  (t) => [
    uniqueIndex("refresh_tokens_hash_unique").on(t.tokenHash),
    index("refresh_tokens_user_idx").on(t.userId),
    index("refresh_tokens_family_idx").on(t.familyId),
  ],
);

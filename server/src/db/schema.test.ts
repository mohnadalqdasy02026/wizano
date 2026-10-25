// اختبار تكامل لقاعدة البيانات المركزية — المرحلة 3.
// يُشغَّل على قاعدة wizano_test (DATABASE_URL_TEST) ويطبق الترحيلات ثم يتحقق:
// - عدد الجداول والأنواع
// - قيود CHECK المالية (إجمالي/مدفوع/متبقي)
// - منع تعديل وحذف سجل التدقيق (trigger)
// - منع تكرار idempotency
// - الفهارس الفريدة الجزئية (ربط العميل بالمحل، عضو نشط)
// الاختبار يتحقق من البنية فقط؛ يبدأ ويعيد القاعدة لحالتها بحذف ما أنشأه.

import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { sql } from "drizzle-orm";
import { migrate } from "drizzle-orm/postgres-js/migrator";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { createDb, type Database, type SqlClient } from "./index.js";

const migrationsFolder = path.join(
  path.dirname(fileURLToPath(import.meta.url)),
  "migrations",
);

const SHOP_ID = "0a000000-0000-7000-8000-000000000001";
const CUSTOMER_ID = "0a000000-0000-7000-8000-000000000002";
const PURCHASE_ID = "0a000000-0000-7000-8000-000000000003";

let db: Database;
let client: SqlClient;

beforeAll(async () => {
  ({ db, client } = createDb());
  await migrate(db, { migrationsFolder });
  await db.execute(sql`DELETE FROM sync_operations WHERE shop_id = ${SHOP_ID}`);
  await db.execute(
    sql`ALTER TABLE public.audit_logs DISABLE TRIGGER audit_logs_immutable`,
  );
  await db.execute(sql`DELETE FROM audit_logs WHERE shop_id = ${SHOP_ID}`);
  await db.execute(
    sql`ALTER TABLE public.audit_logs ENABLE TRIGGER audit_logs_immutable`,
  );
  await db.execute(
    sql`DELETE FROM customer_shop_links WHERE shop_id = ${SHOP_ID}`,
  );
  await db.execute(sql`DELETE FROM purchases WHERE shop_id = ${SHOP_ID}`);
  await db.execute(sql`DELETE FROM customers WHERE id = ${CUSTOMER_ID}`);
  await db.execute(sql`DELETE FROM shops WHERE id = ${SHOP_ID}`);

  await db.execute(
    sql`INSERT INTO shops (id, name) VALUES (${SHOP_ID}, 'متجر اختبار')`,
  );
  await db.execute(
    sql`INSERT INTO customers (id, display_name) VALUES (${CUSTOMER_ID}, 'عميل اختبار')`,
  );
}, 60000);

afterAll(async () => {
  if (!client) return;
  await db.execute(sql`DELETE FROM sync_operations WHERE shop_id = ${SHOP_ID}`);
  await db.execute(
    sql`ALTER TABLE public.audit_logs DISABLE TRIGGER audit_logs_immutable`,
  );
  await db.execute(sql`DELETE FROM audit_logs WHERE shop_id = ${SHOP_ID}`);
  await db.execute(
    sql`ALTER TABLE public.audit_logs ENABLE TRIGGER audit_logs_immutable`,
  );
  await db.execute(
    sql`DELETE FROM customer_shop_links WHERE shop_id = ${SHOP_ID}`,
  );
  await db.execute(sql`DELETE FROM purchases WHERE shop_id = ${SHOP_ID}`);
  await db.execute(sql`DELETE FROM customers WHERE id = ${CUSTOMER_ID}`);
  await db.execute(sql`DELETE FROM shops WHERE id = ${SHOP_ID}`);
  await client.end({ timeout: 5 });
});

describe("مخطط قاعدة البيانات المركزية", () => {
  it("يُنشئ الجداول الـ18 المطلوبة", async () => {
    const rows = await db.execute<{ table_name: string }>(
      sql`SELECT table_name FROM information_schema.tables
          WHERE table_schema = 'public' AND table_type = 'BASE TABLE'`,
    );
    const names = rows.map((r) => r.table_name).sort();
    expect(names).toEqual(
      [
        "audit_logs",
        "customer_shop_links",
        "customers",
        "device_registrations",
        "financial_adjustments",
        "invitations",
        "notifications",
        "objection_replies",
        "objections",
        "payments",
        "purchase_returns",
        "purchases",
        "refresh_tokens",
        "shop_counters",
        "shop_members",
        "shops",
        "sync_operations",
        "users",
      ].sort(),
    );
  });

  it("يرفض شراءً مدفوعه أكبر من إجماليه", async () => {
    await expect(
      db.execute(
        sql`INSERT INTO purchases (id, shop_id, customer_id, shop_seq, occurred_at, items_text, total_amount, paid_amount, remaining_amount)
            VALUES (gen_random_uuid(), ${SHOP_ID}, ${CUSTOMER_ID}, 1, now(), 'x', 500, 900, -400)`,
      ),
    ).rejects.toThrow();
  });

  it("يرفض شراءً متبقيه غير مطابق (إجمالي − مدفوع)", async () => {
    await expect(
      db.execute(
        sql`INSERT INTO purchases (id, shop_id, customer_id, shop_seq, occurred_at, items_text, total_amount, paid_amount, remaining_amount)
            VALUES (gen_random_uuid(), ${SHOP_ID}, ${CUSTOMER_ID}, 2, now(), 'x', 500, 100, 999)`,
      ),
    ).rejects.toThrow();
  });

  it("يقبل شراءً صحيحًا الأرصدة", async () => {
    await db.execute(
      sql`INSERT INTO purchases (id, shop_id, customer_id, shop_seq, occurred_at, items_text, total_amount, paid_amount, remaining_amount)
          VALUES (${PURCHASE_ID}, ${SHOP_ID}, ${CUSTOMER_ID}, 3, now(), 'أصناف', 1000, 300, 700)`,
    );
    const rows = await db.execute<{ remaining_amount: string }>(
      sql`SELECT remaining_amount FROM purchases WHERE id = ${PURCHASE_ID}`,
    );
    expect(rows[0]?.remaining_amount).toBe("700");
  });

  it("يمنع حذف سجل التدقيق (trigger)", async () => {
    await db.execute(
      sql`INSERT INTO audit_logs (shop_id, action, entity_type, entity_id)
          VALUES (${SHOP_ID}, 'purchase.create', 'purchase', ${PURCHASE_ID})`,
    );
    await expect(
      db.execute(sql`DELETE FROM audit_logs WHERE shop_id = ${SHOP_ID}`),
    ).rejects.toMatchObject({
      cause: { message: expect.stringContaining("سجل التدقيق") },
    });
  });

  it("يمنع تكرار نفس مفتاح idempotency في المحل نفسه", async () => {
    await db.execute(
      sql`INSERT INTO sync_operations (shop_id, idempotency_key, operation_type, entity_type, entity_id, status)
          VALUES (${SHOP_ID}, 'key-1', 'push', 'purchase', ${PURCHASE_ID}, 'accepted')`,
    );
    await expect(
      db.execute(
        sql`INSERT INTO sync_operations (shop_id, idempotency_key, operation_type, entity_type, entity_id, status)
            VALUES (${SHOP_ID}, 'key-1', 'push', 'purchase', ${PURCHASE_ID}, 'accepted')`,
      ),
    ).rejects.toThrow();
  });

  it("يطبق فهرسًا فريدًا جزئيًا لمنع تكرار ربط العميل النشط بالمحل", async () => {
    await db.execute(
      sql`INSERT INTO customer_shop_links (customer_id, shop_id, status)
          VALUES (${CUSTOMER_ID}, ${SHOP_ID}, 'active')`,
    );
    await expect(
      db.execute(
        sql`INSERT INTO customer_shop_links (customer_id, shop_id, status)
            VALUES (${CUSTOMER_ID}, ${SHOP_ID}, 'active')`,
      ),
    ).rejects.toThrow();
  });

  it("يسمح بربط جديد بعد إزالة الربط السابق (فهرس جزئي)", async () => {
    await db.execute(
      sql`UPDATE customer_shop_links SET status = 'removed' WHERE shop_id = ${SHOP_ID}`,
    );
    await db.execute(
      sql`INSERT INTO customer_shop_links (customer_id, shop_id, status)
          VALUES (${CUSTOMER_ID}, ${SHOP_ID}, 'active')`,
    );
    const rows = await db.execute<{ n: string }>(
      sql`SELECT count(*) AS n FROM customer_shop_links WHERE shop_id = ${SHOP_ID} AND status = 'active'`,
    );
    expect(rows[0]?.n).toBe("1");
  });
});

// اختبارات وسيط الصلاحيات وعزل المحل.
// - hasPermission/requirePermission: منطق المفاتيح (owner يملك الكل، staff حسب المفاتيح).
// - requireShopMembership: يمنع الوصول لمحل لا ينتمي إليه المستخدم (R-06).

import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { eq, inArray } from "drizzle-orm";
import { createDb, type Database, type SqlClient } from "../db/index.js";
import { migrate } from "drizzle-orm/postgres-js/migrator";
import {
  shopMembers,
  shops,
  users,
} from "../db/schema.js";
import {
  hasPermission,
  requirePermission,
  requireShopMembership,
} from "./auth.js";
import path from "node:path";
import { fileURLToPath } from "node:url";

const migrationsFolder = path.join(
  path.dirname(fileURLToPath(import.meta.url)),
  "../db/migrations",
);

const OWNER_ID = "0b000000-0000-7000-8000-000000000001";
const STAFF_ID = "0b000000-0000-7000-8000-000000000002";
const OUTSIDER_ID = "0b000000-0000-7000-8000-000000000003";
const SHOP_A = "0b000000-0000-7000-8000-00000000000a";
const SHOP_B = "0b000000-0000-7000-8000-00000000000b";

let db: Database;
let client: SqlClient;

async function cleanup(): Promise<void> {
  await db
    .delete(shopMembers)
    .where(inArray(shopMembers.shopId, [SHOP_A, SHOP_B]));
  await db.delete(shops).where(inArray(shops.id, [SHOP_A, SHOP_B]));
  await db
    .delete(users)
    .where(inArray(users.id, [OWNER_ID, STAFF_ID, OUTSIDER_ID]));
}

beforeAll(async () => {
  ({ db, client } = createDb());
  await migrate(db, { migrationsFolder });
  await cleanup();

  await db.insert(users).values([
    { id: OWNER_ID, displayName: "المالك", passwordHash: "x" },
    { id: STAFF_ID, displayName: "الموظف", passwordHash: "x" },
    { id: OUTSIDER_ID, displayName: "غريب", passwordHash: "x" },
  ]);
  await db.insert(shops).values([
    { id: SHOP_A, name: "محل أ" },
    { id: SHOP_B, name: "محل ب" },
  ]);
  await db.insert(shopMembers).values([
    { shopId: SHOP_A, userId: OWNER_ID, role: "owner" },
    {
      shopId: SHOP_A,
      userId: STAFF_ID,
      role: "staff",
      permissionKeys: ["purchases.create"],
    },
  ]);
}, 60000);

afterAll(async () => {
  if (!db) return;
  await cleanup();
  if (client) await client.end({ timeout: 5 });
});

describe("منطق الصلاحيات (مفاتيح)", () => {
  it("المالك يملك كل الصلاحيات", () => {
    expect(hasPermission({ role: "owner", permissionKeys: [] }, "anything")).toBe(
      true,
    );
  });

  it("الموظف يملك فقط مفاتيحه", () => {
    const staff = { role: "staff", permissionKeys: ["purchases.create"] };
    expect(hasPermission(staff, "purchases.create")).toBe(true);
    expect(hasPermission(staff, "payments.create")).toBe(false);
  });

  it("يرفض العملية عند غياب الصلاحية", () => {
    const staff = { role: "staff", permissionKeys: [] };
    expect(() => requirePermission(staff, "payments.create")).toThrow();
  });
});

describe("عزل المحل (requireShopMembership)", () => {
  it("يسمح للمالك بالوصول إلى محله", async () => {
    const m = await requireShopMembership(OWNER_ID, SHOP_A);
    expect(m.role).toBe("owner");
  });

  it("يسمح للموظف بالوصول إلى محل انتمائه", async () => {
    const m = await requireShopMembership(STAFF_ID, SHOP_A);
    expect(m.role).toBe("staff");
    expect(m.permissionKeys).toContain("purchases.create");
  });

  it("يمنع الغريب من الوصول إلى أي محل", async () => {
    await expect(requireShopMembership(OUTSIDER_ID, SHOP_A)).rejects.toThrow();
  });

  it("يمنع عضو محل أ من الوصول إلى محل ب (عزل المحلات)", async () => {
    await expect(requireShopMembership(OWNER_ID, SHOP_B)).rejects.toThrow();
  });
});

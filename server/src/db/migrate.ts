import { migrate } from "drizzle-orm/postgres-js/migrator";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { db, client } from "./index.js";

const migrationsFolder = path.join(
  path.dirname(fileURLToPath(import.meta.url)),
  "migrations",
);

async function main(): Promise<void> {
  if (!fs.existsSync(path.join(migrationsFolder, "meta", "_journal.json"))) {
    console.log("لا توجد ترحيلات بعد (تبدأ من المرحلة 3). إنهاء.");
    await client.end({ timeout: 5 });
    return;
  }
  console.log("بدء تنفيذ الترحيلات...");
  await migrate(db, { migrationsFolder });
  console.log("اكتملت الترحيلات بنجاح.");
  await client.end({ timeout: 5 });
}

main().catch((err) => {
  console.error("فشل تنفيذ الترحيلات:", err);
  process.exit(1);
});

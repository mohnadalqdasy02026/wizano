import { drizzle } from "drizzle-orm/postgres-js";
import postgres from "postgres";
import { databaseUrl, isTest } from "../config/index.js";
import * as schema from "./schema.js";

export type Database = ReturnType<typeof createDb>["db"];
export type SqlClient = ReturnType<typeof createDb>["client"];

export function createDb(url: string = databaseUrl()) {
  const client = postgres(url, {
    max: isTest ? 4 : 10,
    idle_timeout: 20,
    connect_timeout: 10,
  });
  const db = drizzle(client, { schema });
  return { db, client };
}

export const { db, client } = createDb();

export async function pingDb(database: Database = db): Promise<boolean> {
  try {
    await database.execute("SELECT 1");
    return true;
  } catch {
    return false;
  }
}

export async function closeDb(): Promise<void> {
  await client.end({ timeout: 5 });
}

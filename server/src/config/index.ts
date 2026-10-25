import "dotenv/config";
import { z } from "zod";

const envSchema = z.object({
  NODE_ENV: z.enum(["development", "test", "production"]).default("development"),
  LOG_LEVEL: z.enum(["fatal", "error", "warn", "info", "debug", "trace"]).default("info"),
  API_HOST: z.string().default("0.0.0.0"),
  API_PORT: z.coerce
    .number()
    .int()
    .min(1)
    .max(65535)
    .default(process.env.PORT ? Number(process.env.PORT) : 4000),
  CORS_ORIGINS: z.string().default(""),
  TRUST_PROXY: z
    .enum(["true", "false"])
    .default("false")
    .transform((value) => value === "true"),
  DATABASE_URL: z.string().min(1, "DATABASE_URL مطلوب"),
  RATE_LIMIT_GLOBAL_MAX: z.coerce.number().int().positive().default(300),
  RATE_LIMIT_GLOBAL_WINDOW: z.coerce.number().int().positive().default(60000),
  // المصادقة (المرحلة 4). الأسرار إلزامية بطول ≥32 عند التشغيل غير الاختباري.
  JWT_ACCESS_SECRET: z.string().min(32, "JWT_ACCESS_SECRET يجب أن يكون 32 حرفًا على الأقل"),
  ACCESS_TOKEN_TTL_SECONDS: z.coerce.number().int().positive().default(900), // 15 دقيقة
  REFRESH_TOKEN_TTL_DAYS: z.coerce.number().int().positive().default(30),
  // حد المحاولات الخاصة بمسارات المصادقة
  AUTH_RATE_LIMIT_MAX: z.coerce.number().int().positive().default(20),
  AUTH_RATE_LIMIT_WINDOW: z.coerce.number().int().positive().default(60000),
});

export type Env = z.infer<typeof envSchema>;

function loadEnv(): Env {
  const parsed = envSchema.safeParse(process.env);
  if (!parsed.success) {
    const issues = parsed.error.issues
      .map((i) => `${i.path.join(".")}: ${i.message}`)
      .join(" | ");
    throw new Error(`إعدادات البيئة غير صالحة — ${issues}`);
  }
  if (parsed.data.NODE_ENV === "production" && !parsed.data.CORS_ORIGINS.trim()) {
    throw new Error("CORS_ORIGINS مطلوب في بيئة الإنتاج.");
  }
  return parsed.data;
}

export const env = loadEnv();

export const corsOrigins = env.CORS_ORIGINS.split(",")
  .map((o) => o.trim())
  .filter((o) => o.length > 0);

export const isTest = env.NODE_ENV === "test";

export function databaseUrl(): string {
  if (isTest && process.env.DATABASE_URL_TEST) {
    return process.env.DATABASE_URL_TEST;
  }
  return env.DATABASE_URL;
}

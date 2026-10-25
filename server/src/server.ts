import { buildApp } from "./app.js";
import { env } from "./config/index.js";
import { closeDb } from "./db/index.js";

async function main(): Promise<void> {
  const app = await buildApp();

  const shutdown = async (signal: string): Promise<void> => {
    app.log.info(`استلام إشارة ${signal} — إيقاف الخادم بأمان...`);
    try {
      await app.close();
      await closeDb();
      process.exit(0);
    } catch (err) {
      app.log.error(err);
      process.exit(1);
    }
  };

  process.on("SIGINT", () => void shutdown("SIGINT"));
  process.on("SIGTERM", () => void shutdown("SIGTERM"));

  await app.listen({ host: env.API_HOST, port: env.API_PORT });
  app.log.info(
    `WIZANO server يعمل على http://${env.API_HOST}:${env.API_PORT} (بيئة: ${env.NODE_ENV})`,
  );
}

main().catch((err) => {
  console.error("فشل تشغيل الخادم:", err);
  process.exit(1);
});

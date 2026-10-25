import type { FastifyInstance } from "fastify";
import type { Database } from "../../db/index.js";
import { pingDb } from "../../db/index.js";

export interface HealthDeps {
  ping: () => Promise<boolean>;
}

export const defaultHealthDeps: HealthDeps = {
  ping: () => pingDb(),
};

export async function registerHealthRoutes(
  app: FastifyInstance,
  deps: HealthDeps = defaultHealthDeps,
): Promise<void> {
  app.get("/api/v1/health", async () => {
    const dbUp = await deps.ping();
    return {
      data: {
        service: "wizano-server",
        status: dbUp ? "ok" : "degraded",
        db: dbUp ? "up" : "down",
        time: new Date().toISOString(),
      },
    };
  });
}

export type { Database };

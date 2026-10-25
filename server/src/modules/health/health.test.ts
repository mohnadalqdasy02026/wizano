import { describe, expect, it } from "vitest";
import { buildApp } from "../../app.js";

describe("GET /api/v1/health", () => {
  it("يعيد 200 وحالة سليمة عندما تكون قاعدة البيانات متاحة", async () => {
    const app = await buildApp({ healthDeps: { ping: async () => true } });
    const res = await app.inject({ method: "GET", url: "/api/v1/health" });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.data.service).toBe("wizano-server");
    expect(body.data.status).toBe("ok");
    expect(body.data.db).toBe("up");
    await app.close();
  });

  it("يعيد 200 بحالة degraded عندما تفشل قاعدة البيانات", async () => {
    const app = await buildApp({ healthDeps: { ping: async () => false } });
    const res = await app.inject({ method: "GET", url: "/api/v1/health" });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.data.status).toBe("degraded");
    expect(body.data.db).toBe("down");
    await app.close();
  });

  it("يعيد 404 لمسار غير موجود", async () => {
    const app = await buildApp({ healthDeps: { ping: async () => true } });
    const res = await app.inject({ method: "GET", url: "/api/v1/nope" });
    expect(res.statusCode).toBe(404);
    await app.close();
  });
});

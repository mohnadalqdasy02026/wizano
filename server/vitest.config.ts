import { defineConfig } from "vitest/config";
import "dotenv/config";

export default defineConfig({
  test: {
    environment: "node",
    include: ["src/**/*.test.ts"],
    env: {
      NODE_ENV: "test",
      JWT_ACCESS_SECRET:
        process.env.JWT_ACCESS_SECRET ??
        "test-secret-test-secret-test-secret-1234567890",
      DATABASE_URL_TEST: process.env.DATABASE_URL_TEST ?? "",
    },
  },
});

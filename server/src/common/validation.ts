// تحقق موحّد للطلبات — Zod (docs/04-architecture.md §4).

import { ZodError, type ZodType } from "zod";
import { badRequest } from "./errors.js";

// يحوّل فشل Zod إلى خطأ عربي موحّد يحمل تفاصيل الحقول.
export function parseOrThrow<T>(schema: ZodType<T>, body: unknown): T {
  try {
    return schema.parse(body);
  } catch (err) {
    if (err instanceof ZodError) {
      const details = err.issues.map((i) => ({
        field: i.path.join(".") || "(الجسم)",
        message: i.message,
      }));
      throw badRequest("بيانات الطلب غير صالحة.", details);
    }
    throw err;
  }
}

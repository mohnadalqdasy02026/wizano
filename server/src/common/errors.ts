// أخطاء موحّدة للـ API — رسائل عربية + أكواد ثابتة.
// الشكل: { error: { code, message_ar, details? } } كما في docs/04-architecture.md §4.

export class AppError extends Error {
  readonly statusCode: number;
  readonly code: string;
  readonly messageAr: string;
  readonly details?: unknown;

  constructor(
    statusCode: number,
    code: string,
    messageAr: string,
    details?: unknown,
  ) {
    super(messageAr);
    this.name = "AppError";
    this.statusCode = statusCode;
    this.code = code;
    this.messageAr = messageAr;
    this.details = details;
  }
}

export const badRequest = (messageAr: string, details?: unknown) =>
  new AppError(400, "BAD_REQUEST", messageAr, details);

export const unauthorized = (messageAr = "يجب تسجيل الدخول للمتابعة.") =>
  new AppError(401, "UNAUTHORIZED", messageAr);

export const forbidden = (messageAr = "لا تملك صلاحية تنفيذ هذه العملية.") =>
  new AppError(403, "FORBIDDEN", messageAr);

export const notFound = (messageAr = "المورد المطلوب غير موجود.") =>
  new AppError(404, "NOT_FOUND", messageAr);

export const conflict = (messageAr: string, details?: unknown) =>
  new AppError(409, "CONFLICT", messageAr, details);

export const tooManyRequests = (
  messageAr = "محاولات كثيرة. الرجاء المحاولة بعد قليل.",
) => new AppError(429, "TOO_MANY_REQUESTS", messageAr);

export const internal = (messageAr = "حدث خطأ غير متوقع في الخادم.") =>
  new AppError(500, "INTERNAL_ERROR", messageAr);

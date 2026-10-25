/// خطأ مُوحَّد صادر عن طبقة الوصول للبيانات (API).
///
/// يحمل رسالة عربية جاهزة للعرض ورمز HTTP إن وُجد، حتى لا تعتمد الواجهة
/// أبدًا على تفاصيل الاستجابة الخام.
class ApiException implements Exception {
  const ApiException({
    required this.message,
    required this.code,
    this.statusCode,
    this.details,
  });

  /// رسالة عربية جاهزة للعرض للمستخدم.
  final String message;

  /// رمز الخطأ المنطقي من الخادم (مثل BAD_REQUEST، CONFLICT).
  final String code;

  /// رمز HTTP إن كان الخطأ من استجابة الخادم.
  final int? statusCode;

  /// تفاصيل إضافية من الخادم (مثل إصدار الخادم في حالة التعارض).
  final Map<String, dynamic>? details;

  bool get isUnauthorized => statusCode == 401;
  bool get isConflict => statusCode == 409;
  bool get isNetworkError => statusCode == null;

  @override
  String toString() => 'ApiException($code, $statusCode): $message';
}

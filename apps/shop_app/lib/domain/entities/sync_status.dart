/// حالة المزامنة لأي عملية مالية من منظور العميل.
enum SyncStatus {
  /// محفوظة على الخادم ومعتمدة مركزيًا.
  synced,

  /// محفوظة محليًا في انتظار الإرسال (لم تُرسل بعد).
  local,

  /// была في الطابور وفشلت محاولة إرسال (تحتاج معالجة/إعادة محاولة).
  failed,
  /// تعارض: تم تعديل العملية على الخادم من جهاز آخر — يحتاج مراجعة (لا إعادة إرسال).
  conflict,
}

extension SyncStatusX on SyncStatus {
  /// وسم صريح للمستخدم — لا تُعرض أي عملية محلية كأنها معتمدة.
  String get label => switch (this) {
        SyncStatus.synced => 'متزامن',
        SyncStatus.local => 'محلي — غير متزامن',
        SyncStatus.failed => 'تعذّر الإرسال',
        SyncStatus.conflict => 'تعارض — needs review',
      };

  /// هل العملية غير معتمدة مركزيًا بعد؟
  bool get isPending => this == SyncStatus.local || this == SyncStatus.failed;

  bool get isConflict => this == SyncStatus.conflict;

  String get wire => switch (this) {
        SyncStatus.synced => 'synced',
        SyncStatus.local => 'local',
        SyncStatus.failed => 'failed',
        SyncStatus.conflict => 'conflict',
      };

  static SyncStatus fromWire(String value) => switch (value) {
        'synced' => SyncStatus.synced,
        'failed' => SyncStatus.failed,
        'conflict' => SyncStatus.conflict,
        _ => SyncStatus.local,
      };
}

/// نوع العملية في الطابور المحلي.
enum LocalOpType { purchase, payment }

extension LocalOpTypeX on LocalOpType {
  String get wire => switch (this) {
        LocalOpType.purchase => 'purchase',
        LocalOpType.payment => 'payment',
      };

  String get label => switch (this) {
        LocalOpType.purchase => 'مشتريات',
        LocalOpType.payment => 'مدفوعات',
      };

  static LocalOpType fromWire(String value) => value == 'payment'
      ? LocalOpType.payment
      : LocalOpType.purchase;
}

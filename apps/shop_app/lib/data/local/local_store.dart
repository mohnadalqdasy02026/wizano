import 'dart:convert';

import '../../domain/entities/models.dart';
import '../../domain/entities/sync_status.dart';

/// عملية محفوظة محليًا في الطابور.
class QueuedOperation {
  final String id;
  final LocalOpType opType;
  final String shopId;
  final String customerId;
  final String idempotencyKey;
  final Map<String, dynamic> payload;
  final SyncStatus status;
  final int attempts;
  final String? lastError;
  final DateTime createdAt;
  final DateTime updatedAt;

  const QueuedOperation({
    required this.id,
    required this.opType,
    required this.shopId,
    required this.customerId,
    required this.idempotencyKey,
    required this.payload,
    required this.status,
    required this.attempts,
    required this.lastError,
    required this.createdAt,
    required this.updatedAt,
  });

  factory QueuedOperation.fromRow(Map<String, Object?> row) {
    return QueuedOperation(
      id: row['id']! as String,
      opType: LocalOpTypeX.fromWire(row['op_type']! as String),
      shopId: row['shop_id']! as String,
      customerId: row['customer_id']! as String,
      idempotencyKey: row['idempotency_key']! as String,
      payload: jsonDecode(row['payload']! as String) as Map<String, dynamic>,
      status: SyncStatusX.fromWire(row['status']! as String),
      attempts: (row['attempts']! as int?) ?? 0,
      lastError: row['last_error'] as String?,
      createdAt: DateTime.parse(row['created_at']! as String),
      updatedAt: DateTime.parse(row['updated_at']! as String),
    );
  }

  Map<String, Object?> toRow() => {
        'id': id,
        'op_type': opType.wire,
        'shop_id': shopId,
        'customer_id': customerId,
        'idempotency_key': idempotencyKey,
        'payload': jsonEncode(payload),
        'status': status.wire,
        'attempts': attempts,
        'last_error': lastError,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };
}

/// نتيجة محاولة مزامنة واحدة.
class SyncAttempt {
  final int id;
  final String opId;
  final LocalOpType opType;
  final String shopId;
  final SyncAttemptStatus status;
  final String? message;
  final DateTime createdAt;

  const SyncAttempt({
    required this.id,
    required this.opId,
    required this.opType,
    required this.shopId,
    required this.status,
    required this.message,
    required this.createdAt,
  });

  factory SyncAttempt.fromRow(Map<String, Object?> row) {
    return SyncAttempt(
      id: (row['id']! as int),
      opId: row['op_id']! as String,
      opType: LocalOpTypeX.fromWire(row['op_type']! as String),
      shopId: row['shop_id']! as String,
      status: SyncAttemptStatusX.fromWire(row['status']! as String),
      message: row['message'] as String?,
      createdAt: DateTime.parse(row['created_at']! as String),
    );
  }
}

/// حالة محاولة المزامنة الواحدة.
enum SyncAttemptStatus {
  /// اعتمدها الخادم.
  sent,

  /// رفضها الخادم (تحتاج تدخلًا).
  failed,

  /// تعذّر الوصول إلى الخادم.
  offline,
}

extension SyncAttemptStatusX on SyncAttemptStatus {
  /// وسم صريح للمستخدم.
  String get label => switch (this) {
        SyncAttemptStatus.sent => 'أُرسلت واعتُمدت',
        SyncAttemptStatus.failed => 'فشلت — تحتاج تدخلًا',
        SyncAttemptStatus.offline => 'تعذّر الاتصال',
      };

  String get wire => switch (this) {
        SyncAttemptStatus.sent => 'sent',
        SyncAttemptStatus.failed => 'failed',
        SyncAttemptStatus.offline => 'offline',
      };

  static SyncAttemptStatus fromWire(String value) => switch (value) {
        'sent' => SyncAttemptStatus.sent,
        'failed' => SyncAttemptStatus.failed,
        _ => SyncAttemptStatus.offline,
      };
}

/// المخزن المحلي للتطبيق — واجهة واحدة لكل ما يُحفظ على الجهاز:
/// طابور المزامنة، نسخ العرض، سجل المزامنة، ونسخة العملاء.
///
/// مستقلة عن SQLite ليسهل اختبارها ببديل في الذاكرة.
abstract class LocalStore {
  // ---------------------------------------------------------------------------
  // طابور المزامنة
  // ---------------------------------------------------------------------------

  /// العمليات المحفوظة (الأقدم أولًا).
  Future<List<QueuedOperation>> list({String? shopId, SyncStatus? status});

  /// عدد العمليات المحفوظة.
  Future<int> count({String? shopId});

  /// يضيف عملية أو يحدّث موجودة بنفس المعرّف.
  Future<void> enqueue({
    required String id,
    required LocalOpType opType,
    required String shopId,
    required String customerId,
    required String idempotencyKey,
    required Map<String, dynamic> payload,
  });

  /// يحدّث حالة عملية.
  Future<void> updateStatus(
    String id,
    SyncStatus status, {
    String? error,
    bool incrementAttempts = false,
    bool resetAttempts = false,
  });

  /// يقرأ عملية واحدة بمعرّفها.
  Future<QueuedOperation?> findOperation(String id);

  /// يحذف عملية (بعد اعتمادها مركزيًا).
  Future<void> remove(String id);

  /// يفرّغ طابور محل معيّن.
  Future<void> clearShop(String shopId);

  // ---------------------------------------------------------------------------
  // نسخ العرض المحلية
  // ---------------------------------------------------------------------------

  /// يحفظ نسخة العرض المحلية لعملية.
  Future<void> cacheOperation({
    required String id,
    required LocalOpType opType,
    required String shopId,
    required String customerId,
    required Map<String, dynamic> payload,
  });

  /// يقرأ نسخ العرض المحلية.
  Future<List<Map<String, dynamic>>> cachedOperations({
    String? shopId,
    String? customerId,
  });

  /// يحذف نسخة العرض المحلية (بعد اعتماد العملية مركزيًا).
  Future<void> removeCache(String id);

  // ---------------------------------------------------------------------------
  // سجل المزامنة
  // ---------------------------------------------------------------------------

  /// يسجّل محاولة مزامنة (ناجحة أو متعثرة).
  Future<void> logAttempt({
    required String opId,
    required LocalOpType opType,
    required String shopId,
    required SyncAttemptStatus status,
    String? message,
  });

  /// آخر محاولات المزامنة (الأحدث أولًا).
  Future<List<SyncAttempt>> recentAttempts({String? shopId, int limit = 50});

  // ---------------------------------------------------------------------------
  // نسخة العملاء (للقراءة دون اتصال)
  // ---------------------------------------------------------------------------

  /// يستبدل نسخة العملاء المحفوظة لمحل بآخر ما وصل من الخادم.
  Future<void> replaceCustomers(String shopId, List<Customer> customers);

  /// يقرأ نسخة العملاء المحفوظة لمحل.
  Future<List<Customer>> listCustomers(String shopId);

  // ---------------------------------------------------------------------------
  // نسخة المحلات (للقراءة دون اتصال)
  // ---------------------------------------------------------------------------

  /// يستبدل نسخة المحلات المحفوظة بآخر ما وصل من الخادم.
  Future<void> replaceShops(List<Shop> shops);

  /// يقرأ نسخة المحلات المحفوظة.
  Future<List<Shop>> listShops();
}

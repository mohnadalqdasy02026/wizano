import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../domain/entities/models.dart';
import '../../domain/entities/sync_status.dart';
import 'local_database.dart';
import 'local_store.dart';

/// تنفيذ SQLite للمخزن المحلي: الطابور، نسخ العرض، سجل المزامنة، والنسخة للعملاء.
class SqliteLocalStore implements LocalStore {
  SqliteLocalStore(this._db);

  final LocalDatabase _db;

  @override
  Future<List<QueuedOperation>> list({String? shopId, SyncStatus? status}) async {
    final db = await _db.database;
    final where = <String>[];
    final args = <Object?>[];
    if (shopId != null) {
      where.add('shop_id = ?');
      args.add(shopId);
    }
    if (status != null) {
      where.add('status = ?');
      args.add(status.wire);
    }
    final rows = await db.query(
      LocalDatabase.outboxTable,
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'created_at ASC',
    );
    return rows.map(QueuedOperation.fromRow).toList();
  }

  @override
  Future<int> count({String? shopId}) async {
    final db = await _db.database;
    final rows = await db.query(
      LocalDatabase.outboxTable,
      columns: ['id'],
      where: shopId == null ? null : 'shop_id = ?',
      whereArgs: shopId == null ? null : [shopId],
    );
    return rows.length;
  }

  /// يضيف عملية إلى الطابور (أو يحدّث موجودة بنفس المعرّف).
  @override
  Future<void> enqueue({
    required String id,
    required LocalOpType opType,
    required String shopId,
    required String customerId,
    required String idempotencyKey,
    required Map<String, dynamic> payload,
  }) async {
    final db = await _db.database;
    final now = DateTime.now();
    final existing = await db.query(
      LocalDatabase.outboxTable,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      await db.update(
        LocalDatabase.outboxTable,
        {
          'payload': jsonEncode(payload),
          'status': SyncStatus.local.wire,
          'last_error': null,
          'updated_at': now.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      return;
    }
    await db.insert(
      LocalDatabase.outboxTable,
      QueuedOperation(
        id: id,
        opType: opType,
        shopId: shopId,
        customerId: customerId,
        idempotencyKey: idempotencyKey,
        payload: payload,
        status: SyncStatus.local,
        attempts: 0,
        lastError: null,
        createdAt: now,
        updatedAt: now,
      ).toRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// يحدّث حالة عملية في الطابور.
  @override
  Future<void> updateStatus(
    String id,
    SyncStatus status, {
    String? error,
    bool incrementAttempts = false,
    bool resetAttempts = false,
  }) async {
    final db = await _db.database;
    final rows = await db.query(
      LocalDatabase.outboxTable,
      columns: ['attempts'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final attempts = (rows.first['attempts']! as int?) ?? 0;
    await db.update(
      LocalDatabase.outboxTable,
      {
        'status': status.wire,
        'attempts': resetAttempts
            ? 0
            : (incrementAttempts ? attempts + 1 : attempts),
        'last_error': error,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// يقرأ عملية واحدة بمعرّفها.
  @override
  Future<QueuedOperation?> findOperation(String id) async {
    final db = await _db.database;
    final rows = await db.query(
      LocalDatabase.outboxTable,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return QueuedOperation.fromRow(rows.first);
  }

  /// يحذف عملية من الطابور (بعد اعتمادها مركزيًا).
  @override
  Future<void> remove(String id) async {
    final db = await _db.database;
    await db.delete(
      LocalDatabase.outboxTable,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// يفرّغ طابور محل معيّن.
  @override
  Future<void> clearShop(String shopId) async {
    final db = await _db.database;
    await db.delete(
      LocalDatabase.outboxTable,
      where: 'shop_id = ?',
      whereArgs: [shopId],
    );
  }

  // ---------------------------------------------------------------------------
  // نسخة العرض المحلية
  // ---------------------------------------------------------------------------

  /// يحفظ نسخة العرض المحلية لعملية (لعرضها أثناء انقطاع الشبكة).
  @override
  Future<void> cacheOperation({
    required String id,
    required LocalOpType opType,
    required String shopId,
    required String customerId,
    required Map<String, dynamic> payload,
  }) async {
    final db = await _db.database;
    await db.insert(
      LocalDatabase.cacheTable,
      {
        'id': id,
        'op_type': opType.wire,
        'shop_id': shopId,
        'customer_id': customerId,
        'payload': jsonEncode(payload),
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// يقرأ نسخة العرض المحلية لعميل (أو لكل العملاء).
  @override
  Future<List<Map<String, dynamic>>> cachedOperations({
    String? shopId,
    String? customerId,
  }) async {
    final db = await _db.database;
    final where = <String>[];
    final args = <Object?>[];
    if (shopId != null) {
      where.add('shop_id = ?');
      args.add(shopId);
    }
    if (customerId != null) {
      where.add('customer_id = ?');
      args.add(customerId);
    }
    final rows = await db.query(
      LocalDatabase.cacheTable,
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'updated_at DESC',
    );
    return rows
        .map((r) => jsonDecode(r['payload']! as String) as Map<String, dynamic>)
        .toList();
  }

  /// يحذف نسخة العرض المحلية (بعد اعتماد العملية مركزيًا).
  @override
  Future<void> removeCache(String id) async {
    final db = await _db.database;
    await db.delete(
      LocalDatabase.cacheTable,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ---------------------------------------------------------------------------
  // سجل المزامنة
  // ---------------------------------------------------------------------------

  /// يسجّل محاولة مزامنة (ناجحة أو متعثرة).
  @override
  Future<void> logAttempt({
    required String opId,
    required LocalOpType opType,
    required String shopId,
    required SyncAttemptStatus status,
    String? message,
  }) async {
    final db = await _db.database;
    await db.insert(LocalDatabase.syncLogTable, {
      'op_id': opId,
      'op_type': opType.wire,
      'shop_id': shopId,
      'status': status.wire,
      'message': message,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// آخر محاولات المزامنة (الأحدث أولًا).
  @override
  Future<List<SyncAttempt>> recentAttempts({
    String? shopId,
    int limit = 50,
  }) async {
    final db = await _db.database;
    final rows = await db.query(
      LocalDatabase.syncLogTable,
      where: shopId == null ? null : 'shop_id = ?',
      whereArgs: shopId == null ? null : [shopId],
      orderBy: 'created_at DESC, id DESC',
      limit: limit,
    );
    return rows.map(SyncAttempt.fromRow).toList();
  }

  // ---------------------------------------------------------------------------
  // نسخة العملاء (للقراءة دون اتصال)
  // ---------------------------------------------------------------------------

  /// يستبدل نسخة العملاء المحفوظة لمحل بآخر ما وصل من الخادم.
  @override
  Future<void> replaceCustomers(String shopId, List<Customer> customers) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.delete(
        LocalDatabase.customersTable,
        where: 'shop_id = ?',
        whereArgs: [shopId],
      );
      final now = DateTime.now().toIso8601String();
      for (final c in customers) {
        await txn.insert(LocalDatabase.customersTable, {
          'id': c.id,
          'shop_id': shopId,
          'display_name': c.displayName,
          'phone': c.phone,
          'notes': c.notes,
          'archived_at': c.archivedAt,
          'updated_at': now,
        });
      }
    });
  }

  /// يقرأ نسخة العملاء المحفوظة لمحل.
  @override
  Future<List<Customer>> listCustomers(String shopId) async {
    final db = await _db.database;
    final rows = await db.query(
      LocalDatabase.customersTable,
      where: 'shop_id = ?',
      whereArgs: [shopId],
      orderBy: 'display_name ASC',
    );
    return rows
        .map(
          (r) => Customer(
            id: r['id']! as String,
            displayName: r['display_name']! as String,
            phone: r['phone'] as String?,
            notes: r['notes'] as String?,
            archivedAt: r['archived_at'] as String?,
          ),
        )
        .toList();
  }

  // ---------------------------------------------------------------------------
  // نسخة المحلات (للقراءة دون اتصال)
  // ---------------------------------------------------------------------------

  /// يستبدل نسخة المحلات المحفوظة بآخر ما وصل من الخادم.
  @override
  Future<void> replaceShops(List<Shop> shops) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.delete(LocalDatabase.shopsTable);
      final now = DateTime.now().toIso8601String();
      for (final s in shops) {
        await txn.insert(LocalDatabase.shopsTable, {
          'id': s.id,
          'name': s.name,
          'currency': s.currency,
          'timezone': s.timezone,
          'opening_date': s.openingDate,
          'status': s.status,
          'role': s.role,
          'updated_at': now,
        });
      }
    });
  }

  /// يقرأ نسخة المحلات المحفوظة.
  @override
  Future<List<Shop>> listShops() async {
    final db = await _db.database;
    final rows = await db.query(
      LocalDatabase.shopsTable,
      orderBy: 'name ASC',
    );
    return rows
        .map(
          (r) => Shop(
            id: r['id']! as String,
            name: r['name']! as String,
            currency: r['currency']! as String,
            timezone: r['timezone']! as String,
            openingDate: r['opening_date'] as String?,
            status: r['status']! as String,
            role: r['role'] as String?,
          ),
        )
        .toList();
  }
}



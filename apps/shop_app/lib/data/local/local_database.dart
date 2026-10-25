import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// قاعدة البيانات المحلية للتطبيق (sqflite).
///
/// تحتوي على **طابور العمليات الصادرة** (outbox): كل عملية مالية أنشأها
/// صاحب المحل أثناء انقطاع الشبكة تُحفظ هنا وتبقى محفوظة بعد إغلاق التطبيق
/// وإعادة تشغيله، ثم تُرسل للخادم في مرحلة المزامنة.
class LocalDatabase {
  LocalDatabase({this.fileName = 'wizano.db'});

  final String fileName;
  Database? _db;
  Future<Database>? _opening;

  /// جدول الطابور: العمليات المحلية غير المرسلة بعد.
  static const String outboxTable = 'outbox';

  /// جدول نسخة العرض المحلية: آخر نسخة معروفة من كل عملية لكل عميل.
  static const String cacheTable = 'local_cache';

  /// جدول سجل المزامنة: كل محاولة إرسال (ناجحة أو متعثرة).
  static const String syncLogTable = 'sync_log';

  /// جدول نسخة العملاء: آخر نسخة معروفة من عملاء كل محل (للقراءة دون اتصال).
  static const String customersTable = 'customers';

  /// جدول نسخة المحلات: آخر نسخة معروفة من محلات المستخدم (للقراءة دون اتصال).
  static const String shopsTable = 'shops';

  Future<Database> get database async {
    final existing = _db;
    if (existing != null) return existing;
    return _opening ??= _open();
  }

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    final path = p.join(dir, fileName);
    final db = await openDatabase(
      path,
      version: 4,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $outboxTable (
            id TEXT PRIMARY KEY,
            op_type TEXT NOT NULL,
            shop_id TEXT NOT NULL,
            customer_id TEXT NOT NULL,
            idempotency_key TEXT NOT NULL,
            payload TEXT NOT NULL,
            status TEXT NOT NULL,
            attempts INTEGER NOT NULL DEFAULT 0,
            last_error TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_outbox_status ON $outboxTable (status, created_at)',
        );
        await db.execute('''
          CREATE TABLE $cacheTable (
            id TEXT PRIMARY KEY,
            op_type TEXT NOT NULL,
            shop_id TEXT NOT NULL,
            customer_id TEXT NOT NULL,
            payload TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_cache_shop ON $cacheTable (shop_id, customer_id)',
        );
        await _createSyncLog(db);
        await _createCustomers(db);
        await _createShops(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createSyncLog(db);
        }
        if (oldVersion < 3) {
          await _createCustomers(db);
        }
        if (oldVersion < 4) {
          await _createShops(db);
        }
      },
    );
    _db = db;
    _opening = null;
    return db;
  }

  /// ينشئ جدول سجل المزامنة (يُستدعى عند الإنشاء والترقية).
  Future<void> _createSyncLog(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $syncLogTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        op_id TEXT NOT NULL,
        op_type TEXT NOT NULL,
        shop_id TEXT NOT NULL,
        status TEXT NOT NULL,
        message TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sync_log_shop ON $syncLogTable (shop_id, created_at)',
    );
  }

  /// ينشئ جدول نسخة العملاء (يُستدعى عند الإنشاء والترقية).
  Future<void> _createCustomers(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $customersTable (
        id TEXT NOT NULL,
        shop_id TEXT NOT NULL,
        display_name TEXT NOT NULL,
        phone TEXT,
        notes TEXT,
        archived_at TEXT,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (id, shop_id)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_customers_shop ON $customersTable (shop_id, display_name)',
    );
  }

  /// ينشئ جدول نسخة المحلات (يُستدعى عند الإنشاء والترقية).
  Future<void> _createShops(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $shopsTable (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        currency TEXT NOT NULL,
        timezone TEXT NOT NULL,
        opening_date TEXT,
        status TEXT NOT NULL,
        role TEXT,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  /// يمسح كل البيانات المحلية (خروج أو تبديل حساب).
  Future<void> clearAll() async {
    final db = await database;
    await db.delete(outboxTable);
    await db.delete(cacheTable);
    await db.delete(syncLogTable);
    await db.delete(customersTable);
    await db.delete(shopsTable);
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
    _opening = null;
  }
}


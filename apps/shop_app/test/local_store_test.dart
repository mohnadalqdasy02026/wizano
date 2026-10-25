import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shop_app/data/local/local_database.dart';
import 'package:shop_app/data/local/local_store.dart';
import 'package:shop_app/data/local/sqlite_local_store.dart';
import 'package:shop_app/domain/entities/models.dart';
import 'package:shop_app/domain/entities/sync_status.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late LocalDatabase db;
  late SqliteLocalStore queue;

  setUp(() async {
    db = LocalDatabase(fileName: 'wizano_test.db');
    queue = SqliteLocalStore(db);
    final handle = await db.database;
    await handle.delete('outbox');
    await handle.delete('local_cache');
    await handle.delete('sync_log');
    await handle.delete('customers');
    await handle.delete('shops');
  });

  tearDown(() async {
    await db.close();
  });

  test('يحفظ العملية في الطابور ويقرأها', () async {
    await queue.enqueue(
      id: 'op-1',
      opType: LocalOpType.purchase,
      shopId: 'shop-1',
      customerId: 'c1',
      idempotencyKey: 'key-1',
      payload: const {
        'id': 'op-1',
        'customerId': 'c1',
        'itemsText': 'أرز',
        'totalAmount': 10000,
        'paidAmount': 0,
      },
    );

    final ops = await queue.list(shopId: 'shop-1');
    expect(ops, hasLength(1));
    expect(ops.single.opType, LocalOpType.purchase);
    expect(ops.single.status, SyncStatus.local);
    expect(ops.single.payload['itemsText'], 'أرز');
    expect(await queue.count(shopId: 'shop-1'), 1);
  });

  test('يحدّث حالة العملية ويزيد عدد المحاولات', () async {
    await queue.enqueue(
      id: 'op-1',
      opType: LocalOpType.payment,
      shopId: 'shop-1',
      customerId: 'c1',
      idempotencyKey: 'key-1',
      payload: const {'id': 'op-1', 'amount': 4000},
    );

    await queue.updateStatus(
      'op-1',
      SyncStatus.failed,
      error: 'خطأ في الخادم',
      incrementAttempts: true,
    );

    final op = (await queue.list(shopId: 'shop-1')).single;
    expect(op.status, SyncStatus.failed);
    expect(op.attempts, 1);
    expect(op.lastError, 'خطأ في الخادم');
  });

  test('يحفظ نسخة العرض المحلية ويقرأها ثم يحذفها', () async {
    await queue.cacheOperation(
      id: 'op-1',
      opType: LocalOpType.purchase,
      shopId: 'shop-1',
      customerId: 'c1',
      payload: const {
        'id': 'op-1',
        'shopId': 'shop-1',
        'customerId': 'c1',
        'itemsText': 'أرز',
        'totalAmount': 10000,
      },
    );

    final rows = await queue.cachedOperations(shopId: 'shop-1');
    expect(rows, hasLength(1));
    expect(rows.single['itemsText'], 'أرز');

    await queue.removeCache('op-1');
    expect(await queue.cachedOperations(shopId: 'shop-1'), isEmpty);
  });

  test('يحذف العملية من الطابور', () async {
    await queue.enqueue(
      id: 'op-1',
      opType: LocalOpType.purchase,
      shopId: 'shop-1',
      customerId: 'c1',
      idempotencyKey: 'key-1',
      payload: const {'id': 'op-1'},
    );

    await queue.remove('op-1');
    expect(await queue.list(shopId: 'shop-1'), isEmpty);
    expect(await queue.count(shopId: 'shop-1'), 0);
  });

  test('يفرّغ طابور محل معيّن فقط', () async {
    for (final shop in ['shop-1', 'shop-2']) {
      await queue.enqueue(
        id: 'op-$shop',
        opType: LocalOpType.purchase,
        shopId: shop,
        customerId: 'c1',
        idempotencyKey: 'key-$shop',
        payload: const {'id': 'op'},
      );
    }

    await queue.clearShop('shop-1');
    expect(await queue.list(shopId: 'shop-1'), isEmpty);
    expect(await queue.list(shopId: 'shop-2'), hasLength(1));
  });

  test('يسجّل محاولات المزامنة ويقرأها من الأحدث', () async {
    await queue.logAttempt(
      opId: 'op-1',
      opType: LocalOpType.purchase,
      shopId: 'shop-1',
      status: SyncAttemptStatus.sent,
    );
    await queue.logAttempt(
      opId: 'op-2',
      opType: LocalOpType.payment,
      shopId: 'shop-1',
      status: SyncAttemptStatus.failed,
      message: 'بيانات غير صالحة',
    );
    await queue.logAttempt(
      opId: 'op-3',
      opType: LocalOpType.purchase,
      shopId: 'shop-2',
      status: SyncAttemptStatus.offline,
    );

    final shop1 = await queue.recentAttempts(shopId: 'shop-1');
    expect(shop1, hasLength(2));
    expect(shop1.first.opType, LocalOpType.payment);
    expect(shop1.first.status, SyncAttemptStatus.failed);
    expect(shop1.first.message, 'بيانات غير صالحة');
    expect(shop1.last.status, SyncAttemptStatus.sent);

    expect(await queue.recentAttempts(shopId: 'shop-2'), hasLength(1));
  });

  test('يحفظ نسخة العملاء ويقرأها', () async {
    await queue.replaceCustomers('shop-1', const [
      Customer(id: 'c1', displayName: 'أحمد', phone: '777'),
      Customer(id: 'c2', displayName: 'بدر'),
    ]);

    final customers = await queue.listCustomers('shop-1');
    expect(customers, hasLength(2));
    expect(customers.first.displayName, 'أحمد');
    expect(customers.first.phone, '777');
    expect(customers.last.displayName, 'بدر');
    expect(customers.last.phone, isNull);
  });

  test('يستبدل نسخة العملاء بدل التراكم', () async {
    await queue.replaceCustomers('shop-1', const [
      Customer(id: 'c1', displayName: 'أحمد'),
      Customer(id: 'c2', displayName: 'بدر'),
    ]);
    await queue.replaceCustomers('shop-1', const [
      Customer(id: 'c1', displayName: 'أحمد'),
    ]);

    final customers = await queue.listCustomers('shop-1');
    expect(customers, hasLength(1));
    expect(customers.single.id, 'c1');
  });

  test('نسخة العملاء معزولة بين المحلات', () async {
    await queue.replaceCustomers('shop-1', const [
      Customer(id: 'c1', displayName: 'أحمد'),
    ]);
    await queue.replaceCustomers('shop-2', const [
      Customer(id: 'c9', displayName: 'صالح'),
    ]);

    expect(await queue.listCustomers('shop-1'), hasLength(1));
    expect(await queue.listCustomers('shop-2'), hasLength(1));
    expect(
      (await queue.listCustomers('shop-2')).single.displayName,
      'صالح',
    );
  });

  test('يحفظ نسخة المحلات ويقرأها', () async {
    await queue.replaceShops(const [
      Shop(
        id: 'shop-1',
        name: 'محل الاختبار',
        currency: 'YER',
        timezone: 'Asia/Aden',
        status: 'active',
        role: 'owner',
      ),
    ]);

    final shops = await queue.listShops();
    expect(shops, hasLength(1));
    expect(shops.single.name, 'محل الاختبار');
    expect(shops.single.currency, 'YER');
    expect(shops.single.timezone, 'Asia/Aden');
  });

  test('يستبدل نسخة المحلات بدل التراكم', () async {
    await queue.replaceShops(const [
      Shop(
        id: 'shop-1',
        name: 'محل أول',
        currency: 'YER',
        timezone: 'Asia/Aden',
        status: 'active',
      ),
    ]);
    await queue.replaceShops(const [
      Shop(
        id: 'shop-2',
        name: 'محل ثانٍ',
        currency: 'YER',
        timezone: 'Asia/Aden',
        status: 'active',
      ),
    ]);

    final shops = await queue.listShops();
    expect(shops, hasLength(1));
    expect(shops.single.id, 'shop-2');
  });

  group('الاستعادة بعد إعادة التشغيل', () {
    test('البيانات المحلية تصمد بعد إغلاق التطبيق وفتحه', () async {
      const fileName = 'wizano_restart_test.db';
      final first = LocalDatabase(fileName: fileName);
      final firstStore = SqliteLocalStore(first);

      await firstStore.enqueue(
        id: 'op-1',
        opType: LocalOpType.purchase,
        shopId: 'shop-1',
        customerId: 'c1',
        idempotencyKey: 'key-1',
        payload: const {
          'id': 'op-1',
          'customerId': 'c1',
          'itemsText': 'أرز',
          'totalAmount': 10000,
          'paidAmount': 0,
        },
      );
      await firstStore.cacheOperation(
        id: 'op-1',
        opType: LocalOpType.purchase,
        shopId: 'shop-1',
        customerId: 'c1',
        payload: const {
          'id': 'op-1',
          'shopId': 'shop-1',
          'customerId': 'c1',
          'itemsText': 'أرز',
          'totalAmount': 10000,
        },
      );
      await firstStore.replaceCustomers('shop-1', const [
        Customer(id: 'c1', displayName: 'أحمد'),
      ]);

      // إغلاق التطبيق.
      await first.close();

      // فتح التطبيق من جديد.
      final second = LocalDatabase(fileName: fileName);
      final secondStore = SqliteLocalStore(second);

      final operations = await secondStore.list(shopId: 'shop-1');
      expect(operations, hasLength(1));
      expect(operations.single.status, SyncStatus.local);
      expect(operations.single.payload['itemsText'], 'أرز');
      expect(operations.single.idempotencyKey, 'key-1');

      final cached = await secondStore.cachedOperations(shopId: 'shop-1');
      expect(cached, hasLength(1));
      expect(cached.single['itemsText'], 'أرز');

      final customers = await secondStore.listCustomers('shop-1');
      expect(customers, hasLength(1));
      expect(customers.single.displayName, 'أحمد');

      await second.close();
    });
  });
}








import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_app/core/token_store.dart';
import 'package:shop_app/data/local/local_store.dart';
import 'package:shop_app/data/repositories/offline_first_repository.dart';
import 'package:shop_app/data/remote/api_client.dart';
import 'package:shop_app/domain/entities/sync_status.dart';
import 'package:shop_app/features/payments/payment_controller.dart';
import 'package:shop_app/features/purchases/purchase_controller.dart';

import 'support/in_memory_local_store.dart';

ApiClient _api(Future<http.Response> Function(http.Request) handler) {
  return ApiClient(tokenStore: InMemoryTokenStore(), httpClient: MockClient(handler));
}

/// محاكاة انقطاع الشبكة: يرمي استثناء في كل طلب.
Future<http.Response> _offline(http.Request request) async {
  throw Exception('network down');
}

const _purchaseJson = '{"id":"p1","shopId":"shop-1","customerId":"c1",'
    '"shopSeq":"1","occurredAt":"2026-10-20T10:00:00.000Z","itemsText":"أرز",'
    '"totalAmount":"10000","paidAmount":"3000","remainingAmount":"7000",'
    '"notes":null,"status":"active","statusReason":null,"balanceAfter":"7000"}';

void main() {
  group('العمل دون اتصال', () {
    test('عملية الشراء تُحفظ محليًا بوسم «غير متزامن»', () async {
      final store = InMemoryLocalStore();
      final controller = PurchaseController(
        repository: OfflineFirstRepository(
          api: _api(_offline),
          queue: store,
        ),
      );

      controller.setShop('shop-1');
      final result = await controller.add(
        customerId: 'c1',
        itemsText: 'أرز',
        totalAmount: 10000,
        paidAmount: 3000,
      );

      expect(result.error, isNull);
      expect(result.savedLocally, isTrue);
      expect(result.purchase!.syncStatus, SyncStatus.local);
      expect(result.purchase!.syncStatus.isPending, isTrue);
      expect(controller.pendingCount, 1);
      expect(store.operations, hasLength(1));
      expect(store.operations.single.opType, LocalOpType.purchase);
    });

    test('الدفعة تُحفظ محليًا بوسم «غير متزامن»', () async {
      final store = InMemoryLocalStore();
      final controller = PaymentController(
        repository: OfflineFirstRepository(
          api: _api(_offline),
          queue: store,
        ),
      );

      controller.setShop('shop-1');
      final result = await controller.add(customerId: 'c1', amount: 4000);

      expect(result.error, isNull);
      expect(result.savedLocally, isTrue);
      expect(result.payment!.syncStatus, SyncStatus.local);
      expect(controller.pendingCount, 1);
      expect(store.operations.single.opType, LocalOpType.payment);
    });

    test('الخطأ المنطقي من الخادم لا يُحفظ محليًا', () async {
      final store = InMemoryLocalStore();
      final controller = PurchaseController(
        repository: OfflineFirstRepository(
          api: _api((r) async => http.Response(
                '{"error":{"code":"BAD_REQUEST","message_ar":"بيانات الطلب غير صالحة."}}',
                400,
                headers: {'content-type': 'application/json'},
              )),
          queue: store,
        ),
      );

      controller.setShop('shop-1');
      final result = await controller.add(
        customerId: 'c1',
        itemsText: 'أرز',
        totalAmount: 1000,
        paidAmount: 0,
      );

      expect(result.purchase, isNull);
      expect(result.savedLocally, isFalse);
      expect(result.error, 'بيانات الطلب غير صالحة.');
      expect(store.operations, isEmpty);
    });

    test('عند انقطاع الشبكة يعرض السجل النسخة المحلية بلا خطأ', () async {
      final store = InMemoryLocalStore();
      final controller = PurchaseController(
        repository: OfflineFirstRepository(
          api: _api(_offline),
          queue: store,
        ),
      );

      controller.setShop('shop-1');
      await controller.add(
        customerId: 'c1',
        itemsText: 'أرز',
        totalAmount: 10000,
        paidAmount: 0,
      );
      await controller.load();

      expect(controller.error, isNull);
      expect(controller.purchases, hasLength(1));
      expect(controller.purchases.single.syncStatus, SyncStatus.local);
      expect(controller.purchases.single.totalAmount, 10000);
      expect(controller.pendingCount, 1);
    });

    test('العمليات المحلية غير المرسلة تُقرأ من الطابور', () async {
      final store = InMemoryLocalStore();
      final controller = PurchaseController(
        repository: OfflineFirstRepository(
          api: _api(_offline),
          queue: store,
        ),
      );

      controller.setShop('shop-1');
      await controller.add(
        customerId: 'c1',
        itemsText: 'أرز',
        totalAmount: 10000,
        paidAmount: 0,
      );

      final pending = await controller.pendingOperations();
      expect(pending, hasLength(1));
      expect(pending.single.status, SyncStatus.local);
      expect(pending.single.shopId, 'shop-1');
    });
  });

  group('مزامنة الطابور المحلي', () {
    test('يُرسل العمليات المعلّقة ويزيلها من الطابور عند توفّر الشبكة',
        () async {
      final store = InMemoryLocalStore();
      var online = false;
      final controller = PurchaseController(
        repository: OfflineFirstRepository(
          api: _api((r) async {
            if (!online) throw Exception('network down');
            if (r.method == 'POST') {
              return http.Response('{"data":$_purchaseJson}', 201,
                  headers: {'content-type': 'application/json'});
            }
            return http.Response('{"data":{"items":[$_purchaseJson]}}', 200,
                headers: {'content-type': 'application/json'});
          }),
          queue: store,
        ),
      );

      controller.setShop('shop-1');
      await controller.add(
        customerId: 'c1',
        itemsText: 'أرز',
        totalAmount: 10000,
        paidAmount: 3000,
      );
      expect(controller.pendingCount, 1);

      online = true;
      await controller.load();

      expect(store.operations, isEmpty);
      expect(store.cache, isEmpty);
      expect(controller.pendingCount, 0);
      expect(controller.purchases.single.syncStatus, SyncStatus.synced);
    });

    test('العمليات التي يرفضها الخادم تبقى بوسم «تعذّر الإرسال»', () async {
      final store = InMemoryLocalStore();
      final controller = PurchaseController(
        repository: OfflineFirstRepository(
          api: _api((r) async {
            if (r.method == 'POST') {
              return http.Response(
                '{"error":{"code":"BAD_REQUEST","message_ar":"بيانات غير صالحة."}}',
                400,
                headers: {'content-type': 'application/json'},
              );
            }
            return http.Response('{"data":{"items":[]}}', 200,
                headers: {'content-type': 'application/json'});
          }),
          queue: store,
        ),
      );

      // نضع العملية في الطابور يدويًا بحالة «محلي».
      await store.enqueue(
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

      controller.setShop('shop-1');
      await controller.load();

      expect(store.operations, hasLength(1));
      expect(store.operations.single.status, SyncStatus.failed);
      expect(controller.pendingCount, 1);
    });

    test('انقطاع الشبكة أثناء المزامنة يُبقي العمليات كما هي', () async {
      final store = InMemoryLocalStore();
      final repository = OfflineFirstRepository(
        api: _api(_offline),
        queue: store,
      );
      final controller = PurchaseController(repository: repository);

      controller.setShop('shop-1');
      await controller.add(
        customerId: 'c1',
        itemsText: 'أرز',
        totalAmount: 10000,
        paidAmount: 0,
      );

      final report = await repository.syncPending('shop-1');

      expect(report.offline, isTrue);
      expect(report.sent, 0);
      expect(report.remaining, 1);
      expect(store.operations.single.status, SyncStatus.local);
    });

    test('سجل المزامنة يحفظ المحاولات بنتيجتها', () async {
      final store = InMemoryLocalStore();
      var online = false;
      final repository = OfflineFirstRepository(
        api: _api((r) async {
          if (!online) throw Exception('network down');
          return http.Response('{"data":$_purchaseJson}', 201,
              headers: {'content-type': 'application/json'});
        }),
        queue: store,
      );

      // محاولة أولى: انقطاع الشبكة.
      await repository.syncPending('shop-1');
      await store.enqueue(
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
      await repository.syncPending('shop-1');
      expect(store.attempts.single.status, SyncAttemptStatus.offline);

      // محاولة ثانية: عودة الاتصال.
      online = true;
      final report = await repository.syncPending('shop-1');
      expect(report.sent, 1);
      expect(store.attempts.first.status, SyncAttemptStatus.sent);
      expect(store.operations, isEmpty);
    });

    test('انقطاع الشبكة لا يستنفد حدّ محاولات العملية', () async {
      final store = InMemoryLocalStore();
      final repository = OfflineFirstRepository(
        api: _api(_offline),
        queue: store,
      );

      await store.enqueue(
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

      for (var i = 0; i < 8; i++) {
        await repository.syncPending('shop-1');
      }

      final op = store.operations.single;
      expect(op.attempts, 0, reason: 'انقطاع الشبكة ليس خطأ في العملية');
      expect(op.status, SyncStatus.local);
    });
  });

  group('إعادة محاولة عملية واحدة', () {
    test('إعادة المحاولة اليدوية تُرسل العملية وتزيلها من الطابور', () async {
      final store = InMemoryLocalStore();
      var online = false;
      final repository = OfflineFirstRepository(
        api: _api((r) async {
          if (!online) throw Exception('network down');
          return http.Response('{"data":$_purchaseJson}', 201,
              headers: {'content-type': 'application/json'});
        }),
        queue: store,
      );

      await store.enqueue(
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

      online = true;
      final result = await repository.retryOperation('op-1');

      expect(result, SyncAttemptStatus.sent);
      expect(store.operations, isEmpty);
      expect(store.attempts.first.status, SyncAttemptStatus.sent);
    });

    test('فشل الخادم يبقي العملية مع سبب واضح ولا يحذفها', () async {
      final store = InMemoryLocalStore();
      final repository = OfflineFirstRepository(
        api: _api((r) async => http.Response(
              '{"error":{"code":"BAD_REQUEST","message_ar":"بيانات الطلب غير صالحة."}}',
              400,
              headers: {'content-type': 'application/json'},
            )),
        queue: store,
      );

      await store.enqueue(
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

      final result = await repository.retryOperation('op-1');

      expect(result, SyncAttemptStatus.failed);
      expect(store.operations, hasLength(1));
      expect(store.operations.single.status, SyncStatus.failed);
      expect(store.operations.single.lastError, 'بيانات الطلب غير صالحة.');
    });

    test('إعادة المحاولة اليدوية تصفّر عدّاد المحاولات', () async {
      final store = InMemoryLocalStore();
      final repository = OfflineFirstRepository(
        api: _api((r) async => http.Response(
              '{"error":{"code":"BAD_REQUEST","message_ar":"بيانات الطلب غير صالحة."}}',
              400,
              headers: {'content-type': 'application/json'},
            )),
        queue: store,
      );

      await store.enqueue(
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

      await repository.retryOperation('op-1');
      expect(store.operations.single.attempts, 1);

      await repository.retryOperation('op-1');
      expect(store.operations.single.attempts, 1,
          reason: 'الطلب الصريح من المستخدم يصفّر العدّاد');
    });
  });

  group('منع التكرار المالي', () {
    test('إعادة الإرسال تستعمل المعرّف ومفتاح idempotency نفسيهما',
        () async {
      final store = InMemoryLocalStore();
      final requests = <http.Request>[];
      var attempt = 0;
      final repository = OfflineFirstRepository(
        api: _api((r) async {
          requests.add(r);
          attempt++;
          if (attempt == 1) {
            return http.Response(
              '{"error":{"code":"BAD_REQUEST","message_ar":"بيانات الطلب غير صالحة."}}',
              400,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('{"data":$_purchaseJson}', 201,
              headers: {'content-type': 'application/json'});
        }),
        queue: store,
      );

      await store.enqueue(
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
          'idempotencyKey': 'key-1',
        },
      );

      await repository.retryOperation('op-1');
      await repository.retryOperation('op-1');

      expect(requests, hasLength(2));
      final first = jsonDecode(requests.first.body) as Map<String, dynamic>;
      final second = jsonDecode(requests.last.body) as Map<String, dynamic>;
      expect(second['id'], first['id']);
      expect(second['id'], 'op-1');
      expect(
        requests.last.headers['idempotency-key'],
        requests.first.headers['idempotency-key'],
      );
      expect(requests.last.headers['idempotency-key'], 'key-1');
    });

    test('العملية المحلية تُرسل بنفس المعرّف الذي حُفظ محليًا', () async {
      final store = InMemoryLocalStore();
      final requests = <http.Request>[];
      var online = false;
      final repository = OfflineFirstRepository(
        api: _api((r) async {
          if (!online) throw Exception('network down');
          requests.add(r);
          return http.Response('{"data":$_purchaseJson}', 201,
              headers: {'content-type': 'application/json'});
        }),
        queue: store,
      );

      await repository.createPurchase(
        shopId: 'shop-1',
        customerId: 'c1',
        itemsText: 'أرز',
        totalAmount: 10000,
      );
      final queued = store.operations.single;

      online = true;
      await repository.syncPending('shop-1');

      expect(requests, hasLength(1));
      final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
      expect(body['id'], queued.id);
      expect(
        requests.single.headers['idempotency-key'],
        queued.idempotencyKey,
      );
      expect(body['id'], queued.payload['id']);
    });

    test('المزامنة المتزامنة لا تُرسل العملية مرتين', () async {
      final store = InMemoryLocalStore();
      var requests = 0;
      final repository = OfflineFirstRepository(
        api: _api((r) async {
          requests++;
          // تأخير بسيط чтобы تتداخل الطلبات لو لم يكن هناك قفل.
          await Future<void>.delayed(const Duration(milliseconds: 40));
          return http.Response('{"data":$_purchaseJson}', 201,
              headers: {'content-type': 'application/json'});
        }),
        queue: store,
      );

      await store.enqueue(
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

      // أربع طلبات متزامنة (شاشة المشتريات + المدفوعات + المزامنة + العودة).
      await Future.wait([
        repository.syncPending('shop-1'),
        repository.syncPending('shop-1'),
        repository.syncPending('shop-1'),
        repository.syncPending('shop-1'),
      ]);

      expect(requests, 1, reason: 'المزامنة المتزامنة تُسبب تعارضًا على الخادم');
      expect(store.operations, isEmpty);
    });

    test('خطأ مؤقت في الخادم (5xx) لا يُعدّ رفضًا بل يُعاد لاحقًا', () async {
      final store = InMemoryLocalStore();
      final repository = OfflineFirstRepository(
        api: _api((r) async => http.Response(
              '{"error":{"code":"INTERNAL","message_ar":"حدث خطأ غير متوقع في الخادم."}}',
              500,
              headers: {'content-type': 'application/json'},
            )),
        queue: store,
      );

      await store.enqueue(
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

      final report = await repository.syncPending('shop-1');

      expect(report.failed, 0);
      expect(report.remaining, 1);
      expect(store.operations.single.status, SyncStatus.local);
      expect(store.operations.single.attempts, 0);
    });
  });
}





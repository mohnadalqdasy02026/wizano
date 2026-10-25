import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shop_app/core/token_store.dart';
import 'package:shop_app/data/local/local_store.dart';
import 'package:shop_app/data/repositories/offline_first_repository.dart';
import 'package:shop_app/data/remote/api_client.dart';
import 'package:shop_app/domain/entities/sync_status.dart';
import 'package:shop_app/features/sync/sync_controller.dart';

import 'support/in_memory_local_store.dart';

const _purchaseJson = '{"id":"p1","shopId":"shop-1","customerId":"c1",'
    '"shopSeq":"1","occurredAt":"2026-10-20T10:00:00.000Z","itemsText":"أرز",'
    '"totalAmount":"10000","paidAmount":"3000","remainingAmount":"7000",'
    '"notes":null,"status":"active","statusReason":null,"balanceAfter":"7000"}';

void main() {
  group('SyncController', () {
    test('load يقرأ الطابور ويحدّث العدّاد', () async {
      final store = InMemoryLocalStore();
      await store.enqueue(
        id: 'op-1',
        opType: LocalOpType.purchase,
        shopId: 'shop-1',
        customerId: 'c1',
        idempotencyKey: 'key-1',
        payload: const {'id': 'op-1'},
      );

      final controller = SyncController(
        repository: OfflineFirstRepository(
          api: ApiClient(
            tokenStore: InMemoryTokenStore(),
            httpClient: MockClient((r) async => http.Response('{}', 200)),
          ),
          queue: store,
        ),
      );
      controller.setShop('shop-1');
      await controller.load();

      expect(controller.pendingCount, 1);
      expect(controller.stuckCount, 0);
      expect(controller.pending.single.id, 'op-1');
      expect(controller.error, isNull);
    });

    test('syncNow يفرّغ الطابور ويحدّث آخر مزامنة', () async {
      final store = InMemoryLocalStore();
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

      final controller = SyncController(
        repository: OfflineFirstRepository(
          api: ApiClient(
            tokenStore: InMemoryTokenStore(),
            httpClient: MockClient((r) async => http.Response(
                  '{"data":$_purchaseJson}',
                  201,
                  headers: {'content-type': 'application/json'},
                )),
          ),
          queue: store,
        ),
      );
      controller.setShop('shop-1');
      await controller.syncNow();

      expect(controller.pendingCount, 0);
      expect(controller.lastSyncAt, isNotNull);
      expect(controller.error, isNull);
      expect(controller.attempts.first.status, SyncAttemptStatus.sent);
    });

    test('syncNow يعرض رسالة واضحة عند انقطاع الشبكة', () async {
      final store = InMemoryLocalStore();
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

      final controller = SyncController(
        repository: OfflineFirstRepository(
          api: ApiClient(
            tokenStore: InMemoryTokenStore(),
            httpClient: MockClient((r) async => throw Exception('down')),
          ),
          queue: store,
        ),
      );
      controller.setShop('shop-1');
      await controller.syncNow();

      expect(controller.error, isNotNull);
      expect(controller.pendingCount, 1);
      expect(controller.attempts.first.status, SyncAttemptStatus.offline);
    });

    test('العمليات المرفوضة تُحسب كعمليات متعثرة', () async {
      final store = InMemoryLocalStore();
      await store.enqueue(
        id: 'op-1',
        opType: LocalOpType.purchase,
        shopId: 'shop-1',
        customerId: 'c1',
        idempotencyKey: 'key-1',
        payload: const {'id': 'op-1'},
      );
      await store.updateStatus('op-1', SyncStatus.failed, error: 'مرفوضة');

      final controller = SyncController(
        repository: OfflineFirstRepository(
          api: ApiClient(
            tokenStore: InMemoryTokenStore(),
            httpClient: MockClient((r) async => http.Response('{}', 200)),
          ),
          queue: store,
        ),
      );
      controller.setShop('shop-1');
      await controller.load();

      expect(controller.stuckCount, 1);
      expect(controller.pending.single.lastError, 'مرفوضة');
    });

    test('syncNow يفرّغ الطابور حتى لو كان العدّاد في الذاكرة قديمًا',
        () async {
      final store = InMemoryLocalStore();
      final controller = SyncController(
        repository: OfflineFirstRepository(
          api: ApiClient(
            tokenStore: InMemoryTokenStore(),
            httpClient: MockClient((r) async {
              return http.Response(
                '{"data":{"id":"p1","shopId":"shop-1","customerId":"c1",'
                '"shopSeq":"1","occurredAt":"2026-10-20T10:00:00.000Z",'
                '"itemsText":"أرز","totalAmount":"10000","paidAmount":"0",'
                '"remainingAmount":"10000","notes":null,"status":"active",'
                '"statusReason":null,"balanceAfter":"10000"}}',
                201,
                headers: {'content-type': 'application/json'},
              );
            }),
          ),
          queue: store,
        ),
      );
      controller.setShop('shop-1');
      await controller.load();
      expect(controller.pendingCount, 0);

      // عملية أُنشئت بعد آخر قراءة (العدّاد في الذاكرة لم يُحدَّث).
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

      await controller.syncNow();

      expect(store.operations, isEmpty);
      expect(controller.pendingCount, 0);
    });
  });
}



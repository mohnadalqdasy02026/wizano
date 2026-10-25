import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_app/core/token_store.dart';
import 'package:shop_app/data/repositories/offline_first_repository.dart';
import 'package:shop_app/data/remote/api_client.dart';
import 'package:shop_app/features/purchases/purchase_controller.dart';

import 'support/in_memory_local_store.dart';

ApiClient _api(Future<http.Response> Function(http.Request) handler) {
  return ApiClient(tokenStore: InMemoryTokenStore(), httpClient: MockClient(handler));
}

OfflineFirstRepository _repo(Future<http.Response> Function(http.Request) handler) {
  return OfflineFirstRepository(
    api: _api(handler),
    queue: InMemoryLocalStore(),
  );
}

const _purchaseJson = '{"id":"p1","shopId":"shop-1","customerId":"c1",'
    '"shopSeq":"1","occurredAt":"2026-10-20T10:00:00.000Z","itemsText":"أرز",'
    '"totalAmount":"10000","paidAmount":"3000","remainingAmount":"7000",'
    '"notes":null,"status":"active","statusReason":null,"balanceAfter":"7000"}';

void main() {
  group('PurchaseController', () {
    test('load يجلب مشتريات المحل النشط', () async {
      final controller = PurchaseController(
        repository: _repo((r) async => http.Response(
              '{"data":{"items":[$_purchaseJson]}}',
              200,
              headers: {'content-type': 'application/json'},
            )),
      );

      controller.setShop('shop-1');
      await controller.load();

      expect(controller.purchases, hasLength(1));
      expect(controller.purchases.single.remainingAmount, 7000);
      expect(controller.error, isNull);
    });

    test('لا يُحمّل شيئًا بلا محل نشط', () async {
      final controller = PurchaseController(
        repository: _repo((r) async => http.Response('{}', 200)),
      );

      await controller.load();
      expect(controller.purchases, isEmpty);
    });

    test('add يضيف العملية إلى القائمة', () async {
      final controller = PurchaseController(
        repository: _repo((r) async {
          if (r.method == 'POST') {
            return http.Response('{"data":$_purchaseJson}', 201,
                headers: {'content-type': 'application/json'});
          }
          return http.Response('{"data":{"items":[]}}', 200,
              headers: {'content-type': 'application/json'});
        }),
      );

      controller.setShop('shop-1');
      final result = await controller.add(
        customerId: 'c1',
        itemsText: 'أرز',
        totalAmount: 10000,
        paidAmount: 3000,
      );

      expect(result.error, isNull);
      expect(result.purchase?.shopSeq, '1');
      expect(controller.purchases.single.totalAmount, 10000);
    });

    test('add يعيد رسالة الخطأ العربية عند الفشل', () async {
      final controller = PurchaseController(
        repository: _repo((r) async => http.Response(
              '{"error":{"code":"BAD_REQUEST","message_ar":"بيانات الطلب غير صالحة."}}',
              400,
              headers: {'content-type': 'application/json'},
            )),
      );

      controller.setShop('shop-1');
      final result = await controller.add(
        customerId: 'c1',
        itemsText: 'x',
        totalAmount: 1000,
        paidAmount: 2000,
      );

      expect(result.purchase, isNull);
      expect(result.error, 'بيانات الطلب غير صالحة.');
    });
  });
}



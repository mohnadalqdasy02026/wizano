import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_app/core/token_store.dart';
import 'package:shop_app/data/repositories/offline_first_repository.dart';
import 'package:shop_app/data/remote/api_client.dart';
import 'package:shop_app/features/payments/payment_controller.dart';

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

const _paymentJson = '{"id":"pay1","shopId":"shop-1","customerId":"c1",'
    '"purchaseId":null,"amount":"4000","paidAt":"2026-10-20T10:00:00.000Z",'
    '"shopSeq":"1","notes":null,"balanceAfter":"6000"}';

void main() {
  group('PaymentController', () {
    test('load يجلب مدفوعات المحل النشط', () async {
      final controller = PaymentController(
        repository: _repo((r) async => http.Response(
              '{"data":{"items":[$_paymentJson]}}',
              200,
              headers: {'content-type': 'application/json'},
            )),
      );

      controller.setShop('shop-1');
      await controller.load();

      expect(controller.payments, hasLength(1));
      expect(controller.payments.single.amount, 4000);
      expect(controller.payments.single.balanceAfter, 6000);
      expect(controller.error, isNull);
    });

    test('لا يُحمّل شيئًا بلا محل نشط', () async {
      final controller = PaymentController(
        repository: _repo((r) async => http.Response('{}', 200)),
      );

      await controller.load();
      expect(controller.payments, isEmpty);
    });

    test('add يضيف الدفعة إلى القائمة', () async {
      final controller = PaymentController(
        repository: _repo((r) async {
          if (r.method == 'POST') {
            return http.Response('{"data":$_paymentJson}', 201,
                headers: {'content-type': 'application/json'});
          }
          return http.Response('{"data":{"items":[]}}', 200,
              headers: {'content-type': 'application/json'});
        }),
      );

      controller.setShop('shop-1');
      final result = await controller.add(customerId: 'c1', amount: 4000);

      expect(result.error, isNull);
      expect(result.payment?.shopSeq, '1');
      expect(controller.payments.single.amount, 4000);
    });

    test('add يعيد رسالة الخطأ العربية عند الفشل', () async {
      final controller = PaymentController(
        repository: _repo((r) async => http.Response(
              '{"error":{"code":"BAD_REQUEST","message_ar":"المبلغ يتجاوز إجمالي المتبقي على العميل."}}',
              400,
              headers: {'content-type': 'application/json'},
            )),
      );

      controller.setShop('shop-1');
      final result = await controller.add(customerId: 'c1', amount: 99999);

      expect(result.payment, isNull);
      expect(result.error, 'المبلغ يتجاوز إجمالي المتبقي على العميل.');
    });
  });
}



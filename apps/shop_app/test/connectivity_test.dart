import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shop_app/core/api_exception.dart';
import 'package:shop_app/core/connectivity.dart';
import 'package:shop_app/core/token_store.dart';
import 'package:shop_app/data/remote/api_client.dart';
import 'package:shop_app/data/repositories/offline_first_repository.dart';

import 'support/in_memory_local_store.dart';

ApiClient _api(Future<http.Response> Function(http.Request) handler) {
  return ApiClient(tokenStore: InMemoryTokenStore(), httpClient: MockClient(handler));
}

Future<http.Response> _offline(http.Request request) async {
  throw Exception('network down');
}

void main() {
  group('مراقب الاتصال', () {
    test('يعلن انقطاع الشبكة عند فشل الطلب ويُعلن عودة الاتصال', () async {
      final monitor = ConnectivityMonitor();
      var online = false;
      final repository = OfflineFirstRepository(
        api: _api((r) async {
          if (!online) throw Exception('network down');
          return http.Response('{"data":{"items":[]}}', 200,
              headers: {'content-type': 'application/json'});
        }),
        queue: InMemoryLocalStore(),
        monitor: monitor,
      );

      expect(monitor.offline, isFalse);

      await expectLater(
        repository.listRemote('shop-1'),
        throwsA(isA<ApiException>()),
      );
      expect(monitor.offline, isTrue);
      expect(monitor.offlineSince, isNotNull);

      online = true;
      await repository.listRemote('shop-1');
      expect(monitor.offline, isFalse);
      expect(monitor.offlineSince, isNull);
    });

    test('رفض الخادم لا يُعلن انقطاع الشبكة', () async {
      final monitor = ConnectivityMonitor();
      final repository = OfflineFirstRepository(
        api: _api((r) async => http.Response(
              '{"error":{"code":"BAD_REQUEST","message_ar":"بيانات غير صالحة."}}',
              400,
              headers: {'content-type': 'application/json'},
            )),
        queue: InMemoryLocalStore(),
        monitor: monitor,
      );

      await repository.createPurchase(
        shopId: 'shop-1',
        customerId: 'c1',
        itemsText: 'أرز',
        totalAmount: 1000,
      );

      expect(monitor.offline, isFalse);
    });

    test('حفظ عملية محليًا يعلن انقطاع الشبكة', () async {
      final monitor = ConnectivityMonitor();
      final repository = OfflineFirstRepository(
        api: _api(_offline),
        queue: InMemoryLocalStore(),
        monitor: monitor,
      );

      final result = await repository.createPurchase(
        shopId: 'shop-1',
        customerId: 'c1',
        itemsText: 'أرز',
        totalAmount: 1000,
      );

      expect(result.savedLocally, isTrue);
      expect(monitor.offline, isTrue);
    });

    test('الإشعار لا يتكرر عند تكرار النتيجة نفسها', () async {
      final monitor = ConnectivityMonitor();
      var notifications = 0;
      monitor.addListener(() => notifications++);

      monitor.reportOffline();
      monitor.reportOffline();
      expect(notifications, 1);

      monitor.reportOnline();
      monitor.reportOnline();
      expect(notifications, 2);
    });
  });
}

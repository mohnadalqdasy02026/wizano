import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_app/core/token_store.dart';
import 'package:shop_app/data/repositories/offline_first_repository.dart';
import 'package:shop_app/data/remote/api_client.dart';
import 'package:shop_app/features/customers/customer_controller.dart';

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

const _customersJson = '{"data":{"items":[{"id":"c1","displayName":"أحمد",'
    '"phone":null,"notes":null,"archivedAt":null}]}}';

Future<http.Response> _offline(http.Request request) async {
  throw Exception('network down');
}

void main() {
  group('CustomerController', () {
    test('load يجلب عملاء المحل النشط', () async {
      final controller = CustomerController(
        api: _api((r) async => http.Response(
              _customersJson,
              200,
              headers: {'content-type': 'application/json'},
            )),
        repository: _repo((r) async => http.Response(
              _customersJson,
              200,
              headers: {'content-type': 'application/json'},
            )),
      );

      controller.setShop('shop-1');
      await controller.load();

      expect(controller.customers, hasLength(1));
      expect(controller.error, isNull);
      expect(controller.offline, isFalse);
    });

    test('لا يُحمّل شيئًا بلا محل نشط', () async {
      final controller = CustomerController(
        api: _api((r) async => http.Response('{}', 200)),
        repository: _repo((r) async => http.Response('{}', 200)),
      );

      await controller.load();
      expect(controller.customers, isEmpty);
    });

    test('add يضيف العميل إلى القائمة مرتبة', () async {
      final controller = CustomerController(
        api: _api((r) async {
          if (r.method == 'POST') {
            return http.Response(
              '{"data":{"id":"c9","displayName":"بدر","phone":null,'
              '"notes":null,"archivedAt":null}}',
              201,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('{"data":{"items":[]}}', 200,
              headers: {'content-type': 'application/json'});
        }),
        repository: _repo((r) async => http.Response('{"data":{"items":[]}}', 200,
            headers: {'content-type': 'application/json'})),
      );

      controller.setShop('shop-1');
      final error = await controller.add(displayName: 'بدر');

      expect(error, isNull);
      expect(controller.customers.single.displayName, 'بدر');
    });

    test('add يعيد رسالة الخطأ العربية عند الفشل', () async {
      final controller = CustomerController(
        api: _api((r) async => http.Response(
              '{"error":{"code":"BAD_REQUEST","message_ar":"بيانات الطلب غير صالحة."}}',
              400,
              headers: {'content-type': 'application/json'},
            )),
        repository: _repo((r) async => http.Response('{}', 200)),
      );

      controller.setShop('shop-1');
      final error = await controller.add(displayName: 'x');

      expect(error, 'بيانات الطلب غير صالحة.');
    });
  });

  group('العملاء دون اتصال', () {
    test('يُعرض آخر نسخة محفوظة عند انقطاع الشبكة', () async {
      var online = true;
      final store = InMemoryLocalStore();
      final controller = CustomerController(
        api: _api((r) async {
          if (!online) throw Exception('network down');
          return http.Response(
            _customersJson,
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
        repository: OfflineFirstRepository(
          api: _api((r) async {
            if (!online) throw Exception('network down');
            return http.Response(
              _customersJson,
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
          queue: store,
        ),
      );

      controller.setShop('shop-1');
      await controller.load();
      expect(controller.customers, hasLength(1));
      expect(controller.offline, isFalse);

      online = false;
      await controller.load();

      expect(controller.customers, hasLength(1));
      expect(controller.customers.single.displayName, 'أحمد');
      expect(controller.offline, isTrue);
      expect(controller.error, isNull);
    });

    test('رسالة واضحة عندما لا يوجد اتصال ولا نسخة محفوظة', () async {
      final controller = CustomerController(
        api: _api(_offline),
        repository: OfflineFirstRepository(
          api: _api(_offline),
          queue: InMemoryLocalStore(),
        ),
      );

      controller.setShop('shop-1');
      await controller.load();

      expect(controller.customers, isEmpty);
      expect(controller.offline, isTrue);
      expect(controller.error, isNotNull);
    });

    test('التصفية المحلية تعمل دون اتصال', () async {
      var online = true;
      final controller = CustomerController(
        api: _api((r) async {
          if (!online) throw Exception('network down');
          return http.Response(
            _customersJson,
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
        repository: OfflineFirstRepository(
          api: _api((r) async {
            if (!online) throw Exception('network down');
            return http.Response(
              _customersJson,
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
          queue: InMemoryLocalStore(),
        ),
      );

      controller.setShop('shop-1');
      await controller.load();
      online = false;
      await controller.load(search: 'أحم');

      expect(controller.customers, hasLength(1));
      await controller.load(search: 'لا يوجد');
      expect(controller.customers, isEmpty);
    });
  });
}


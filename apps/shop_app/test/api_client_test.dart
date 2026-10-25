import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_app/core/token_store.dart';
import 'package:shop_app/data/remote/api_client.dart';

void main() {
  group('ApiClient.getHealth', () {
    test('حالة ok عند استجابة سليمة من الخادم وقاعدة البيانات', () async {
      final client = ApiClient(
        tokenStore: InMemoryTokenStore(),
        httpClient: MockClient((request) async => http.Response(
              '{"data":{"service":"wizano-server","status":"ok","db":"up"}}',
              200,
            )),
      );

      final result = await client.getHealth();
      expect(result.status, ServerStatus.ok);
      expect(result.isReachable, isTrue);
    });

    test('حالة degraded عندما تكون قاعدة البيانات معطلة', () async {
      final client = ApiClient(
        tokenStore: InMemoryTokenStore(),
        httpClient: MockClient((request) async => http.Response(
              '{"data":{"service":"wizano-server","status":"degraded","db":"down"}}',
              200,
            )),
      );

      final result = await client.getHealth();
      expect(result.status, ServerStatus.degraded);
      expect(result.isReachable, isTrue);
    });

    test('حالة offline عند فشل الاتصال', () async {
      final client = ApiClient(
        tokenStore: InMemoryTokenStore(),
        httpClient: MockClient((request) async {
          throw http.ClientException('refused');
        }),
      );

      final result = await client.getHealth();
      expect(result.status, ServerStatus.offline);
      expect(result.isReachable, isFalse);
    });

    test('حالة offline عند رمز استجابة غير 200', () async {
      final client = ApiClient(
        tokenStore: InMemoryTokenStore(),
        httpClient: MockClient((request) async => http.Response('err', 500)),
      );

      final result = await client.getHealth();
      expect(result.status, ServerStatus.offline);
    });
  });
}

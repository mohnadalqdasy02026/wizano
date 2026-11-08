import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_app/core/api_exception.dart';
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

  group('ApiClient — تجديد الجلسة', () {
    const jsonHeaders = {'content-type': 'application/json; charset=utf-8'};

    http.Response unauthorized() => http.Response(
          jsonEncode({
            'error': {'code': 'UNAUTHORIZED', 'message_ar': 'انتهت الجلسة.'},
          }),
          401,
          headers: jsonHeaders,
        );

    test('عدة 401 متزامنة تُجدد الرمز مرة واحدة فقط', () async {
      final store = InMemoryTokenStore();
      await store.saveTokens(
        accessToken: 'old-access',
        refreshToken: 'old-refresh',
      );
      var refreshCalls = 0;

      final client = ApiClient(
        tokenStore: store,
        httpClient: MockClient((request) async {
          if (request.url.path == '/api/v1/auth/refresh') {
            refreshCalls++;
            await Future<void>.delayed(const Duration(milliseconds: 30));
            return http.Response(
              jsonEncode({
                'data': {
                  'tokens': {
                    'accessToken': 'new-access',
                    'refreshToken': 'new-refresh',
                    'tokenType': 'Bearer',
                    'expiresIn': 900,
                  },
                },
              }),
              200,
              headers: jsonHeaders,
            );
          }
          if (request.headers['authorization'] == 'Bearer new-access') {
            return http.Response(
              jsonEncode({'data': {'items': <dynamic>[]}}),
              200,
              headers: jsonHeaders,
            );
          }
          return unauthorized();
        }),
      );

      await Future.wait([
        client.listShops(),
        client.listShops(),
        client.listShops(),
      ]);

      expect(refreshCalls, 1);
      expect(await store.readAccessToken(), 'new-access');
      expect(await store.readRefreshToken(), 'new-refresh');
    });

    test('رفض رمز التجديد يمسح الجلسة ويُعلم مرة واحدة', () async {
      final store = InMemoryTokenStore();
      await store.saveTokens(
        accessToken: 'old-access',
        refreshToken: 'dead-refresh',
      );
      var expiredCalls = 0;

      final client = ApiClient(
        tokenStore: store,
        httpClient: MockClient((request) async => unauthorized()),
      );
      client.onSessionExpired = () => expiredCalls++;

      await expectLater(
        client.listShops(),
        throwsA(isA<ApiException>()),
      );

      expect(expiredCalls, 1);
      expect(await store.readAccessToken(), isNull);
      expect(await store.readRefreshToken(), isNull);
    });

    test('فشل الشبكة أثناء التجديد لا يمسح الجلسة', () async {
      final store = InMemoryTokenStore();
      await store.saveTokens(
        accessToken: 'old-access',
        refreshToken: 'keep-refresh',
      );
      var expiredCalls = 0;

      final client = ApiClient(
        tokenStore: store,
        httpClient: MockClient((request) async {
          if (request.url.path == '/api/v1/auth/refresh') {
            throw http.ClientException('offline');
          }
          return unauthorized();
        }),
      );
      client.onSessionExpired = () => expiredCalls++;

      await expectLater(
        client.listShops(),
        throwsA(isA<ApiException>()),
      );

      expect(expiredCalls, 0);
      expect(await store.readRefreshToken(), 'keep-refresh');
    });
  });

  group('ApiClient baseUrl security', () {
    test('يرفض رابط http غير محلي', () {
      expect(
        () => ApiClient(
          tokenStore: InMemoryTokenStore(),
          baseUrl: 'http://example.com',
        ),
        throwsArgumentError,
      );
    });

    test('يقبل رابط https', () {
      final client = ApiClient(
        tokenStore: InMemoryTokenStore(),
        baseUrl: 'https://example.com',
      );
      expect(client.baseUrl, 'https://example.com');
    });

    test('يسمح localhost في التطوير', () {
      final client = ApiClient(
        tokenStore: InMemoryTokenStore(),
        baseUrl: 'http://localhost:4000',
      );
      expect(client.baseUrl, 'http://localhost:4000');
    });
  });
}

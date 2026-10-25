import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_app/core/api_exception.dart';
import 'package:shop_app/core/token_store.dart';
import 'package:shop_app/data/remote/api_client.dart';

const _sessionBody = '''
{"data":{"user":{"id":"u1","displayName":"مالك","email":"a@b.com","phone":null},
"tokens":{"accessToken":"access-1","refreshToken":"refresh-1","tokenType":"Bearer","expiresIn":900}}}
''';

void main() {
  group('ApiClient المصادقة', () {
    test('login يعيد الجلسة ويحفظ الرموز في TokenStore', () async {
      final store = InMemoryTokenStore();
      final api = ApiClient(
        tokenStore: store,
        httpClient: MockClient((request) async {
          expect(request.url.path, '/api/v1/auth/login');
          return http.Response(_sessionBody, 200,
              headers: {'content-type': 'application/json'});
        }),
      );

      final session = await api.login(email: 'a@b.com', password: 'secret');

      expect(session.user.displayName, 'مالك');
      expect(session.tokens.accessToken, 'access-1');
    });

    test('register يرسل الحقول الصحيحة', () async {
      final store = InMemoryTokenStore();
      late Map<String, dynamic> sent;
      final api = ApiClient(
        tokenStore: store,
        httpClient: MockClient((request) async {
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(_sessionBody, 201,
              headers: {'content-type': 'application/json'});
        }),
      );

      await api.register(
        displayName: 'مالك',
        email: 'a@b.com',
        password: 'secret123',
      );

      expect(sent['displayName'], 'مالك');
      expect(sent['email'], 'a@b.com');
      expect(sent['password'], 'secret123');
    });

    test('يرفع خطأ عربي موحّد عند الاستجابة بخطأ', () async {
      final store = InMemoryTokenStore();
      final api = ApiClient(
        tokenStore: store,
        httpClient: MockClient((request) async => http.Response(
              '{"error":{"code":"CONFLICT","message_ar":"البريد الإلكتروني مستخدم بالفعل."}}',
              409,
              headers: {'content-type': 'application/json'},
            )),
      );

      expect(
        () => api.register(
          displayName: 'مالك',
          email: 'a@b.com',
          password: 'secret123',
        ),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 409)
            .having((e) => e.isConflict, 'isConflict', true)
            .having((e) => e.message, 'message',
                'البريد الإلكتروني مستخدم بالفعل.')),
      );
    });

    test('يجدد الرمز مرة واحدة عند 401 ثم يعيد المحاولة', () async {
      final store = InMemoryTokenStore();
      await store.saveTokens(accessToken: 'old', refreshToken: 'refresh-1');
      var refreshCalls = 0;

      final api = ApiClient(
        tokenStore: store,
        httpClient: MockClient((request) async {
          if (request.url.path == '/api/v1/auth/refresh') {
            refreshCalls++;
            return http.Response(
              '{"data":{"user":{"id":"u1","displayName":"مالك","email":"a@b.com","phone":null},'
              '"tokens":{"accessToken":"new-access","refreshToken":"refresh-2","tokenType":"Bearer","expiresIn":900}}}',
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          final auth = request.headers['authorization'];
          if (auth == 'Bearer new-access') {
            return http.Response(
              '{"data":{"user":{"id":"u1","displayName":"مالك","email":"a@b.com","phone":null},"memberships":[]}}',
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            '{"error":{"code":"UNAUTHORIZED","message_ar":"انتهت الجلسة."}}',
            401,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final user = await api.me();

      expect(user.displayName, 'مالك');
      expect(refreshCalls, 1);
      expect(await store.readAccessToken(), 'new-access');
    });
  });

  group('ApiClient المحلات', () {
    test('listShops يعيد قائمة المحلات مع الدور', () async {
      final api = ApiClient(
        tokenStore: InMemoryTokenStore(),
        httpClient: MockClient((request) async => http.Response(
              '{"data":{"items":[{"id":"s1","name":"بقالة","currency":"YER",'
              '"timezone":"Asia/Aden","openingDate":null,"status":"active","role":"owner"}]}}',
              200,
              headers: {'content-type': 'application/json'},
            )),
      );

      final shops = await api.listShops();
      expect(shops, hasLength(1));
      expect(shops.first.name, 'بقالة');
      expect(shops.first.isOwner, isTrue);
    });

    test('createShop يرسل الحقول ويعيد المحل', () async {
      late Map<String, dynamic> sent;
      final api = ApiClient(
        tokenStore: InMemoryTokenStore(),
        httpClient: MockClient((request) async {
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            '{"data":{"id":"s2","name":"متجر","currency":"YER",'
            '"timezone":"Asia/Aden","openingDate":"2026-01-01","status":"active"}}',
            201,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final shop = await api.createShop(
        name: 'متجر',
        currency: 'YER',
        timezone: 'Asia/Aden',
        openingDate: '2026-01-01',
      );

      expect(sent['name'], 'متجر');
      expect(shop.openingDate, '2026-01-01');
    });
  });

  group('ApiClient العملاء', () {
    test('listCustomers يبني مسار المحل ويدعم البحث', () async {
      late Uri calledUri;
      final api = ApiClient(
        tokenStore: InMemoryTokenStore(),
        httpClient: MockClient((request) async {
          calledUri = request.url;
          return http.Response(
            '{"data":{"items":[{"id":"c1","displayName":"أحمد","phone":"777",'
            '"notes":null,"archivedAt":null}]}}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final customers = await api.listCustomers('shop-1', search: 'أحمد');

      expect(calledUri.path, '/api/v1/shops/shop-1/customers');
      expect(calledUri.queryParameters['search'], 'أحمد');
      expect(customers, hasLength(1));
      expect(customers.first.displayName, 'أحمد');
    });

    test('createCustomer يرسل الحقول ويعيد العميل', () async {
      late Map<String, dynamic> sent;
      final api = ApiClient(
        tokenStore: InMemoryTokenStore(),
        httpClient: MockClient((request) async {
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            '{"data":{"id":"c2","displayName":"سالم","phone":"777","notes":null,"archivedAt":null}}',
            201,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final customer = await api.createCustomer(
        'shop-1',
        displayName: 'سالم',
        phone: '777',
      );

      expect(sent['displayName'], 'سالم');
      expect(customer.phone, '777');
    });

    test('archiveCustomer يقبل استجابة 204 بلا جسم', () async {
      final api = ApiClient(
        tokenStore: InMemoryTokenStore(),
        httpClient: MockClient((request) async {
          expect(request.method, 'DELETE');
          return http.Response('', 204);
        }),
      );

      await api.archiveCustomer('shop-1', 'c3');
    });

    test('createInvitation يعيد الرمز', () async {
      final api = ApiClient(
        tokenStore: InMemoryTokenStore(),
        httpClient: MockClient((request) async => http.Response(
              '{"data":{"id":"i1","code":"AB23CD45","status":"pending",'
              '"expiresAt":"2026-02-01T00:00:00.000Z"}}',
              201,
              headers: {'content-type': 'application/json'},
            )),
      );

      final invite = await api.createInvitation('shop-1', 'c1');
      expect(invite.code, 'AB23CD45');
      expect(invite.status, 'pending');
    });
  });
}

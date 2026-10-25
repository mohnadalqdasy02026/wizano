import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_app/core/token_store.dart';
import 'package:shop_app/data/remote/api_client.dart';
import 'package:shop_app/main.dart';

ApiClient _client({
  required Future<http.Response> Function(http.Request) handler,
  TokenStore? store,
}) {
  return ApiClient(
    tokenStore: store ?? InMemoryTokenStore(),
    httpClient: MockClient(handler),
  );
}

void main() {
  testWidgets('S01 يُعرض أثناء فحص الجلسة غير المعروفة', (tester) async {
    final store = InMemoryTokenStore();
    final api = _client(handler: (r) async => http.Response('{}', 401));
    await tester.pumpWidget(WizanoShopApp(apiClient: api, tokenStore: store));

    expect(find.text('WIZANO | وزانو'), findsWidgets);
    expect(find.text('جارٍ التهيئة...'), findsOneWidget);

    await tester.pumpAndSettle();
  });

  testWidgets('S02 يُعرض عند غياب الجلسة (بلا رمز)', (tester) async {
    final store = InMemoryTokenStore();
    final api = _client(handler: (r) async => http.Response('{}', 401));
    await tester.pumpWidget(WizanoShopApp(apiClient: api, tokenStore: store));
    await tester.pumpAndSettle();

    expect(find.text('تسجيل الدخول'), findsWidgets);
    expect(find.widgetWithText(ElevatedButton, 'دخول'), findsOneWidget);
  });

  testWidgets('S02 يعرض رسالة خطأ عربية عند فشل الدخول', (tester) async {
    final store = InMemoryTokenStore();
    final api = _client(handler: (r) async {
      if (r.url.path == '/api/v1/auth/login') {
        return http.Response(
          '{"error":{"code":"UNAUTHORIZED","message_ar":"البريد/الهاتف أو كلمة المرور غير صحيحة."}}',
          401,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 401);
    });

    await tester.pumpWidget(WizanoShopApp(apiClient: api, tokenStore: store));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextFormField, 'البريد الإلكتروني'), 'a@b.com');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'كلمة المرور'), 'wrongpass');
    await tester.tap(find.widgetWithText(ElevatedButton, 'دخول'));
    await tester.pumpAndSettle();

    expect(find.text('البريد/الهاتف أو كلمة المرور غير صحيحة.'), findsOneWidget);
  });

  testWidgets('يهبط إلى S04 إعداد المحل بعد الدخول بلا محل', (tester) async {
    final store = InMemoryTokenStore();
    final api = _client(
      store: store,
      handler: (r) async {
        switch (r.url.path) {
          case '/api/v1/auth/login':
            return http.Response(
              '{"data":{"user":{"id":"u1","displayName":"مالك","email":"a@b.com","phone":null},'
              '"tokens":{"accessToken":"access-1","refreshToken":"refresh-1","tokenType":"Bearer","expiresIn":900}}}',
              200,
              headers: {'content-type': 'application/json'},
            );
          case '/api/v1/shops':
            return http.Response('{"data":{"items":[]}}', 200,
                headers: {'content-type': 'application/json'});
          default:
            return http.Response('{}', 404);
        }
      },
    );

    await tester.pumpWidget(WizanoShopApp(apiClient: api, tokenStore: store));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextFormField, 'البريد الإلكتروني'), 'a@b.com');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'كلمة المرور'), 'secret123');
    await tester.tap(find.widgetWithText(ElevatedButton, 'دخول'));
    await tester.pumpAndSettle();

    expect(find.text('إعداد المحل'), findsWidgets);
    expect(find.widgetWithText(ElevatedButton, 'حفظ ومتابعة'), findsOneWidget);
  });
}


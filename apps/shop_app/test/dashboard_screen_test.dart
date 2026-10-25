import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shop_app/app/theme.dart';
import 'package:shop_app/core/token_store.dart';
import 'package:shop_app/data/repositories/auth_repository.dart';
import 'package:shop_app/data/repositories/offline_first_repository.dart';
import 'package:shop_app/data/remote/api_client.dart';
import 'package:shop_app/features/auth/auth_controller.dart';
import 'package:shop_app/features/customers/customer_controller.dart';
import 'package:shop_app/features/home/dashboard_screen.dart';
import 'package:shop_app/features/payments/payment_controller.dart';
import 'package:shop_app/features/purchases/purchase_controller.dart';
import 'package:shop_app/features/shop/shop_controller.dart';
import 'package:shop_app/features/sync/sync_controller.dart';
import 'package:shop_app/domain/entities/models.dart';

import 'support/in_memory_local_store.dart';

const _purchaseJson = '{"id":"p1","shopId":"shop-1","customerId":"c1",'
    '"shopSeq":"1","occurredAt":"2026-10-20T10:00:00.000Z","itemsText":"أرز",'
    '"totalAmount":"10000","paidAmount":"3000","remainingAmount":"7000",'
    '"notes":null,"status":"active","statusReason":null,"balanceAfter":"7000"}';

const _shopJson = '{"id":"shop-1","name":"محل الاختبار","currency":"YER",'
    '"timezone":"Asia/Aden","openingDate":null,"status":"active","role":"owner"}';

ApiClient _api(Future<http.Response> Function(http.Request) handler) {
  return ApiClient(tokenStore: InMemoryTokenStore(), httpClient: MockClient(handler));
}

Future<http.Response> _offline(http.Request request) async {
  throw Exception('network down');
}

/// API يردّ بالمحل فقط، ويفشل في بقية المسارات.
Future<http.Response> _shopsOnly(http.Request request) async {
  if (request.url.path.endsWith('/shops')) {
    return http.Response('{"data":{"items":[$_shopJson]}}', 200,
        headers: {'content-type': 'application/json'});
  }
  throw Exception('network down');
}

class _FakeAuthRepository implements AuthRepository {
  @override
  Future<User?> currentUser() async =>
      const User(id: 'u1', displayName: 'مالك', email: 'a@b.com');

  @override
  Future<bool> hasStoredSession() async => true;

  @override
  Future<User?> cachedUser() async =>
      const User(id: 'u1', displayName: 'مالك', email: 'a@b.com');

  @override
  Future<void> logout() async {}

  @override
  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<AuthSession> register({
    required String displayName,
    required String email,
    required String password,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<String?> readActiveShopId() async => 'shop-1';

  @override
  Future<void> setActiveShopId(String? shopId) async {}
}

Widget _app(Widget child) {
  return MaterialApp(
    theme: WizanoTheme.light,
    locale: const Locale('ar'),
    supportedLocales: const [Locale('ar')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    builder: (context, c) =>
        Directionality(textDirection: TextDirection.rtl, child: c!),
    home: child,
  );
}

void main() {
  testWidgets('S06 يحسب إجمالي الديون من العمليات المعتمدة فقط',
      (tester) async {
    final repository = OfflineFirstRepository(
      api: _api(_offline),
      queue: InMemoryLocalStore(),
    );
    final auth = AuthController(repository: _FakeAuthRepository());
    await auth.bootstrap();
    final purchases = PurchaseController(repository: repository);
    final payments = PaymentController(repository: repository);
    final sync = SyncController(repository: repository);

    purchases.setShop('shop-1');
    payments.setShop('shop-1');
    sync.setShop('shop-1');

    // عملية محلية (غير مرسلة) — يجب ألا تُحتسب في الإجمالي.
    await purchases.add(
      customerId: 'c1',
      itemsText: 'سكر',
      totalAmount: 5000,
      paidAmount: 0,
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PurchaseController>.value(value: purchases),
          ChangeNotifierProvider<PaymentController>.value(value: payments),
          ChangeNotifierProvider<SyncController>.value(value: sync),
          ChangeNotifierProvider<AuthController>.value(value: auth),
          ChangeNotifierProvider<ShopController>(
            create: (_) => ShopController(
              api: _api(_shopsOnly),
              repository: OfflineFirstRepository(
                api: _api(_shopsOnly),
                queue: InMemoryLocalStore(),
              ),
            ),
          ),
          ChangeNotifierProvider<CustomerController>(
            create: (_) => CustomerController(
              api: _api(_offline),
              repository: OfflineFirstRepository(
                api: _api(_offline),
                queue: InMemoryLocalStore(),
              ),
            ),
          ),
        ],
        child: _app(const DashboardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // إجمالي الديون = 0 لأن العملية المحلية غير معتمدة.
    expect(find.text('إجمالي الديون'), findsOneWidget);
    expect(find.text('0'), findsWidgets);
    // ملاحظة صريحة بأن العمليات المحلية غير محسوبة.
    expect(
      find.textContaining('لم تُحتسب في الإجماليات'),
      findsOneWidget,
    );
    // العملية المحلية تظهر في «آخر العمليات» بوسم صريح.
    expect(find.text('سكر'), findsOneWidget);
    expect(find.text('محلي — غير متزامن'), findsOneWidget);
  });

  testWidgets('S06 يعرض مبيعات العمليات المعتمدة', (tester) async {
    final repository = OfflineFirstRepository(
      api: _api((r) async {
        if (r.url.path.endsWith('/purchases')) {
          return http.Response('{"data":{"items":[$_purchaseJson]}}', 200,
              headers: {'content-type': 'application/json'});
        }
        if (r.url.path.endsWith('/shops')) {
          return http.Response('{"data":{"items":[$_shopJson]}}', 200,
              headers: {'content-type': 'application/json'});
        }
        throw Exception('network down');
      }),
      queue: InMemoryLocalStore(),
    );
    final auth = AuthController(repository: _FakeAuthRepository());
    await auth.bootstrap();
    final purchases = PurchaseController(repository: repository);
    final payments = PaymentController(repository: repository);
    final sync = SyncController(repository: repository);

    purchases.setShop('shop-1');
    payments.setShop('shop-1');
    sync.setShop('shop-1');
    await purchases.load();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PurchaseController>.value(value: purchases),
          ChangeNotifierProvider<PaymentController>.value(value: payments),
          ChangeNotifierProvider<SyncController>.value(value: sync),
          ChangeNotifierProvider<AuthController>.value(value: auth),
          ChangeNotifierProvider<ShopController>(
            create: (_) => ShopController(
              api: _api(_shopsOnly),
              repository: OfflineFirstRepository(
                api: _api(_shopsOnly),
                queue: InMemoryLocalStore(),
              ),
            ),
          ),
          ChangeNotifierProvider<CustomerController>(
            create: (_) => CustomerController(
              api: _api(_offline),
              repository: OfflineFirstRepository(
                api: _api(_offline),
                queue: InMemoryLocalStore(),
              ),
            ),
          ),
        ],
        child: _app(const DashboardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // المتبقي من العملية المعتمدة = 7000.
    expect(find.text('7000'), findsOneWidget);
    expect(find.text('أرز'), findsOneWidget);
    expect(find.textContaining('لم تُحتسب في الإجماليات'), findsNothing);
  });

  testWidgets('S06 لا يعرض أرقامًا مضللة دون اتصال', (tester) async {
    final repository = OfflineFirstRepository(
      api: _api(_offline),
      queue: InMemoryLocalStore(),
    );
    final purchases = PurchaseController(repository: repository);
    final payments = PaymentController(repository: repository);
    final sync = SyncController(repository: repository);
    final auth = AuthController(repository: _FakeAuthRepository());
    await auth.bootstrap();

    // نسخة المحلات محفوظة محليًا (كأنها جُلبت سابقًا).
    final shopStore = InMemoryLocalStore();
    await shopStore.replaceShops(const [
      Shop(
        id: 'shop-1',
        name: 'محل الاختبار',
        currency: 'YER',
        timezone: 'Asia/Aden',
        status: 'active',
      ),
    ]);

    purchases.setShop('shop-1');
    payments.setShop('shop-1');
    sync.setShop('shop-1');
    await purchases.load();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PurchaseController>.value(value: purchases),
          ChangeNotifierProvider<PaymentController>.value(value: payments),
          ChangeNotifierProvider<SyncController>.value(value: sync),
          ChangeNotifierProvider<AuthController>.value(value: auth),
          ChangeNotifierProvider<ShopController>(
            create: (_) => ShopController(
              api: _api(_offline),
              repository: OfflineFirstRepository(
                api: _api(_offline),
                queue: shopStore,
              ),
            ),
          ),
          ChangeNotifierProvider<CustomerController>(
            create: (_) => CustomerController(
              api: _api(_offline),
              repository: OfflineFirstRepository(
                api: _api(_offline),
                queue: InMemoryLocalStore(),
              ),
            ),
          ),
        ],
        child: _app(const DashboardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // الرقم غير معروف (لا صفر مضلِّل).
    expect(find.text('—'), findsNWidgets(2));
    expect(
      find.textContaining('الأرقام المالية غير معروفة دون اتصال'),
      findsOneWidget,
    );
  });
}







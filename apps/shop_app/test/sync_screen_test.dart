import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shop_app/app/theme.dart';
import 'package:shop_app/core/token_store.dart';
import 'package:shop_app/data/repositories/offline_first_repository.dart';
import 'package:shop_app/data/remote/api_client.dart';
import 'package:shop_app/domain/entities/sync_status.dart';
import 'package:shop_app/features/payments/payment_controller.dart';
import 'package:shop_app/features/purchases/purchase_controller.dart';
import 'package:shop_app/features/sync/sync_controller.dart';
import 'package:shop_app/features/sync/sync_screen.dart';

import 'support/in_memory_local_store.dart';

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
  testWidgets('S08 يعرض عملية في الطابور مع وصفها وزر إعادة المحاولة',
      (tester) async {
    final store = InMemoryLocalStore();
    final repository = OfflineFirstRepository(
      api: ApiClient(
        tokenStore: InMemoryTokenStore(),
        httpClient: MockClient((r) async => throw Exception('down')),
      ),
      queue: store,
    );
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

    final sync = SyncController(repository: repository)..setShop('shop-1');
    final purchases = PurchaseController(repository: repository)..setShop('shop-1');
    final payments = PaymentController(repository: repository)..setShop('shop-1');

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SyncController>.value(value: sync),
          ChangeNotifierProvider<PurchaseController>.value(value: purchases),
          ChangeNotifierProvider<PaymentController>.value(value: payments),
        ],
        child: _app(const SyncScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('في الطابور (1)'), findsOneWidget);
    expect(find.text('أرز — 10000'), findsOneWidget);
    expect(find.text('محلي — غير متزامن'), findsOneWidget);
    expect(find.byTooltip('إعادة محاولة'), findsOneWidget);
    expect(find.text('مزامنة الآن'), findsOneWidget);
  });

  testWidgets('S08 يعرض حالة فارغة حين لا يوجد طابور', (tester) async {
    final store = InMemoryLocalStore();
    final repository = OfflineFirstRepository(
      api: ApiClient(
        tokenStore: InMemoryTokenStore(),
        httpClient: MockClient((r) async => http.Response('{}', 200)),
      ),
      queue: store,
    );

    final sync = SyncController(repository: repository)..setShop('shop-1');
    final purchases = PurchaseController(repository: repository)..setShop('shop-1');
    final payments = PaymentController(repository: repository)..setShop('shop-1');

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SyncController>.value(value: sync),
          ChangeNotifierProvider<PurchaseController>.value(value: purchases),
          ChangeNotifierProvider<PaymentController>.value(value: payments),
        ],
        child: _app(const SyncScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('لا عمليات في الطابور — كل شيء مُرسل.'), findsOneWidget);
    expect(find.text('في الطابور: 0 — متعثر: 0'), findsOneWidget);
    expect(find.text('لم تُجرَ مزامنة بعد'), findsOneWidget);
  });
}

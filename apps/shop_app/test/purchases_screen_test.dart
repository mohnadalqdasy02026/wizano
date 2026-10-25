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
import 'package:shop_app/features/purchases/purchase_controller.dart';
import 'package:shop_app/features/purchases/purchases_screen.dart';

import 'support/in_memory_local_store.dart';

ApiClient _api(Future<http.Response> Function(http.Request) handler) {
  return ApiClient(tokenStore: InMemoryTokenStore(), httpClient: MockClient(handler));
}

Future<http.Response> _offline(http.Request request) async {
  throw Exception('network down');
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
  testWidgets('S13-entry يعرض وسم «محلي — غير متزامن» ولافتة الطابور',
      (tester) async {
    final controller = PurchaseController(
      repository: OfflineFirstRepository(
        api: _api(_offline),
        queue: InMemoryLocalStore(),
      ),
    );
    controller.setShop('shop-1');
    await controller.add(
      customerId: 'c1',
      itemsText: 'أرز',
      totalAmount: 10000,
      paidAmount: 0,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<PurchaseController>.value(
        value: controller,
        child: _app(const PurchasesScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('محلي — غير متزامن'), findsOneWidget);
    expect(find.text('يوجد 1 عملية محلية غير متزامنة'), findsOneWidget);
    expect(find.text('1 غير متزامن'), findsOneWidget);
  });

  testWidgets('S13-entry لا يعرض وسومًا لعمليات مُرسلة', (tester) async {
    final controller = PurchaseController(
      repository: OfflineFirstRepository(
        api: _api((r) async => http.Response(
              '{"data":{"items":[{"id":"p1","shopId":"shop-1","customerId":"c1",'
              '"shopSeq":"1","occurredAt":"2026-10-20T10:00:00.000Z",'
              '"itemsText":"أرز","totalAmount":"10000","paidAmount":"3000",'
              '"remainingAmount":"7000","notes":null,"status":"active",'
              '"statusReason":null,"balanceAfter":"7000"}]}}',
              200,
              headers: {'content-type': 'application/json'},
            )),
        queue: InMemoryLocalStore(),
      ),
    );
    controller.setShop('shop-1');
    await controller.load();

    await tester.pumpWidget(
      ChangeNotifierProvider<PurchaseController>.value(
        value: controller,
        child: _app(const PurchasesScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('محلي — غير متزامن'), findsNothing);
    expect(find.text('يوجد 1 عملية محلية غير متزامنة'), findsNothing);
  });
}


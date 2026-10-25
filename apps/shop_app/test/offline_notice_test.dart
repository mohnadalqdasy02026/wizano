import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_app/app/widgets.dart';

Widget _app(Widget child) {
  return MaterialApp(
    locale: const Locale('ar'),
    supportedLocales: const [Locale('ar')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    builder: (context, c) =>
        Directionality(textDirection: TextDirection.rtl, child: c!),
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets('شريط عدم الاتصال يوضّح أن العمليات تُحفظ محليًا', (tester) async {
    await tester.pumpWidget(_app(const OfflineStrip()));

    expect(find.textContaining('لا يوجد اتصال بالخادم'), findsOneWidget);
    expect(find.textContaining('تُحفظ محليًا'), findsOneWidget);
  });

  testWidgets('تنبيه النموذج يوضّح متى تُحفظ العملية', (tester) async {
    await tester.pumpWidget(_app(const OfflineNotice()));

    expect(
      find.text('لا يوجد اتصال بالخادم — ستُحفظ العملية محليًا وتُرسل لاحقًا.'),
      findsOneWidget,
    );
  });

  testWidgets('تنبيه النموذج يقبل رسالة مخصصة', (tester) async {
    await tester.pumpWidget(
      _app(const OfflineNotice(message: 'الدفعة محليًا')),
    );

    expect(find.text('الدفعة محليًا'), findsOneWidget);
  });
}

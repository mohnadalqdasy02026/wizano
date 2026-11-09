import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_app/domain/entities/models.dart';
import 'package:shop_app/features/customers/customer_picker.dart';

const _customers = [
  Customer(id: 'c1', displayName: 'أحمد القدسي', phone: '771111111'),
  Customer(id: 'c2', displayName: 'محمد علي', phone: '772222222'),
  Customer(id: 'c3', displayName: 'سالم صالح'),
];

Widget _app({ValueChanged<String?>? onChanged}) => MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            child: CustomerPickerField(
              customers: _customers,
              onChanged: onChanged ?? (_) {},
              validator: (v) => v == null ? 'اختر العميل' : null,
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('يفتح البحث ويعرض كل العملاء', (tester) async {
    await tester.pumpWidget(_app());
    await tester.tap(find.text('ابحث واختر العميل'));
    await tester.pumpAndSettle();

    expect(find.text('أحمد القدسي'), findsOneWidget);
    expect(find.text('محمد علي'), findsOneWidget);
    expect(find.text('سالم صالح'), findsOneWidget);
  });

  testWidgets('يبحث بالاسم ويتجاهل الهمزات', (tester) async {
    await tester.pumpWidget(_app());
    await tester.tap(find.text('ابحث واختر العميل'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'احمد');
    await tester.pumpAndSettle();

    expect(find.text('أحمد القدسي'), findsOneWidget);
    expect(find.text('محمد علي'), findsNothing);
    expect(find.text('سالم صالح'), findsNothing);
  });

  testWidgets('يبحث برقم الهاتف ويختار العميل', (tester) async {
    String? selected;
    await tester.pumpWidget(_app(onChanged: (v) => selected = v));
    await tester.tap(find.text('ابحث واختر العميل'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '7722');
    await tester.pumpAndSettle();
    expect(find.text('محمد علي'), findsOneWidget);

    await tester.tap(find.text('محمد علي'));
    await tester.pumpAndSettle();

    expect(selected, 'c2');
    expect(find.text('محمد علي'), findsOneWidget);
  });
}

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_app/core/token_store.dart';
import 'package:shop_app/data/remote/api_client.dart';
import 'package:shop_app/domain/entities/models.dart';
import 'package:shop_app/features/statements/statement_controller.dart';

ApiClient _api(Future<http.Response> Function(http.Request) handler) {
  return ApiClient(tokenStore: InMemoryTokenStore(), httpClient: MockClient(handler));
}

const _statementJson = '{"customerId":"c1","totalPurchases":"15000",'
    '"totalPayments":"4000","balance":"11000","entries":['
    '{"id":"p1","type":"purchase","shopSeq":"1","occurredAt":"2026-10-20T10:00:00.000Z",'
    '"description":"بضاعة","effect":"10000","balanceAfter":"10000","status":"active","purchaseId":null},'
    '{"id":"pay1","type":"payment","shopSeq":"1","occurredAt":"2026-10-21T10:00:00.000Z",'
    '"description":"دفعة","effect":"-4000","balanceAfter":"6000","status":"active","purchaseId":"p1"}'
    ']}';

void main() {
  group('StatementController', () {
    test('load يجلب كشف الحساب مع الإجماليات والعمليات', () async {
      final controller = StatementController(
        api: _api((r) async => http.Response(
              '{"data":$_statementJson}',
              200,
              headers: {'content-type': 'application/json'},
            )),
      );

      await controller.load('shop-1', 'c1');

      final statement = controller.statement;
      expect(statement, isNotNull);
      expect(statement!.balance, 11000);
      expect(statement.totalPurchases, 15000);
      expect(statement.totalPayments, 4000);
      expect(statement.entries, hasLength(2));
      expect(statement.entries.first.isPurchase, isTrue);
      expect(statement.entries.first.effect, 10000);
      expect(statement.entries[1].effect, -4000);
      expect(statement.entries[1].balanceAfter, 6000);
      expect(statement.entries[1].purchaseId, 'p1');
      expect(controller.error, isNull);
    });

    test('يمرّر نوع التصفية في الطلب', () async {
      late Uri captured;
      final controller = StatementController(
        api: _api((r) async {
          captured = r.url;
          return http.Response('{"data":$_statementJson}', 200,
              headers: {'content-type': 'application/json'});
        }),
      );

      await controller.load('shop-1', 'c1', type: 'payment');

      expect(captured.queryParameters['type'], 'payment');
    });

    test('يعيد رسالة الخطأ العربية عند الفشل', () async {
      final controller = StatementController(
        api: _api((r) async => http.Response(
              '{"error":{"code":"NOT_FOUND","message_ar":"العميل غير موجود."}}',
              404,
              headers: {'content-type': 'application/json'},
            )),
      );

      await controller.load('shop-1', 'c1');

      expect(controller.statement, isNull);
      expect(controller.error, 'العميل غير موجود.');
    });

    test('StatementEntry يفسّر الأثر والرصيد الجاري', () {
      final entry = StatementEntry.fromJson({
        'id': 'x',
        'type': 'payment',
        'shopSeq': '5',
        'occurredAt': '2026-10-21T10:00:00.000Z',
        'description': 'دفعة عامة',
        'effect': '-1500',
        'balanceAfter': '8500',
        'status': 'active',
        'purchaseId': null,
      });

      expect(entry.isPurchase, isFalse);
      expect(entry.effect, -1500);
      expect(entry.balanceAfter, 8500);
      expect(entry.shopSeq, '5');
    });
  });
}

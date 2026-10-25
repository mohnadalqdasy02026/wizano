import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_app/core/token_store.dart';
import 'package:shop_app/data/remote/api_client.dart';
import 'package:shop_app/domain/entities/models.dart';
import 'package:shop_app/features/finance/finance_controller.dart';

ApiClient _api(Future<http.Response> Function(http.Request) handler) {
  return ApiClient(tokenStore: InMemoryTokenStore(), httpClient: MockClient(handler));
}

const _returnJson = '{"id":"r1","shopId":"s1","customerId":"c1","purchaseId":"p1",'
    '"amount":"2000","reason":"تالف","occurredAt":"2026-10-21T10:00:00.000Z",'
    '"balanceAfter":"5000","createdAt":"2026-10-21T10:00:00.000Z",'
    '"updatedAt":"2026-10-21T10:00:00.000Z"}';

const _adjustmentJson = '{"id":"a1","shopId":"s1","customerId":"c1",'
    '"relatedPurchaseId":null,"kind":"correction","amount":"500","reason":"تصحيح",'
    '"occurredAt":"2026-10-21T10:00:00.000Z","balanceAfter":"5500",'
    '"createdAt":"2026-10-21T10:00:00.000Z","updatedAt":"2026-10-21T10:00:00.000Z"}';

const _cancelJson = '{"id":"a2","shopId":"s1","customerId":"c1",'
    '"relatedPurchaseId":"p1","kind":"cancellation","amount":"-5000","reason":"إلغاء",'
    '"occurredAt":"2026-10-21T10:00:00.000Z","balanceAfter":"0",'
    '"createdAt":"2026-10-21T10:00:00.000Z","updatedAt":"2026-10-21T10:00:00.000Z"}';

void main() {
  group('FinanceController', () {
    test('addReturn يسجّل مرتجعًا ويضيفه للقائمة', () async {
      final controller = FinanceController(
        api: _api((r) async => http.Response('{"data":$_returnJson}', 201,
            headers: {'content-type': 'application/json'})),
      )..setShop('s1');

      final result = await controller.addReturn(purchaseId: 'p1', amount: 2000);

      expect(result.error, isNull);
      expect(result.returnEntry, isNotNull);
      expect(result.returnEntry!.amount, 2000);
      expect(result.returnEntry!.balanceAfter, 5000);
      expect(controller.returns, hasLength(1));
    });

    test('addAdjustment يرسل المبلغ الموقّع والسبب ويضيفه', () async {
      late http.Request captured;
      final controller = FinanceController(
        api: _api((r) async {
          captured = r;
          return http.Response('{"data":$_adjustmentJson}', 201,
              headers: {'content-type': 'application/json'});
        }),
      )..setShop('s1');

      final result = await controller.addAdjustment(
        customerId: 'c1',
        amount: -1200,
        reason: 'خصم',
      );

      expect(result.error, isNull);
      expect(result.adjustment!.amount, 500);
      expect(captured.url.path, contains('/shops/s1/adjustments'));
      expect(captured.body, contains('-1200'));
      expect(captured.body, contains('خصم'));
    });

    test('cancelPurchase يعيد قيد الإلغاء العكسي', () async {
      final controller = FinanceController(
        api: _api((r) async => http.Response('{"data":$_cancelJson}', 201,
            headers: {'content-type': 'application/json'})),
      )..setShop('s1');

      final result = await controller.cancelPurchase(purchaseId: 'p1', reason: 'إلغاء', version: 1);

      expect(result.error, isNull);
      expect(result.adjustment!.isCancellation, isTrue);
      expect(result.adjustment!.amount, -5000);
      expect(result.adjustment!.balanceAfter, 0);
    });

    test('يعيد رسالة الخطأ العربية عند الفشل', () async {
      final controller = FinanceController(
        api: _api((r) async => http.Response(
              '{"error":{"code":"BAD_REQUEST","message_ar":"قيمة المرتجع تتجاوز المتبقي على العملية."}}',
              400,
              headers: {'content-type': 'application/json'},
            )),
      )..setShop('s1');

      final result = await controller.addReturn(purchaseId: 'p1', amount: 999999);

      expect(result.returnEntry, isNull);
      expect(result.error, 'قيمة المرتجع تتجاوز المتبقي على العملية.');
    });

    test('loadAuditLogs يجلب السجل', () async {
      const logsJson = '{"items":[{"id":"log1","shopId":"s1","actorUserId":"u1",'
          '"action":"purchase.return","entityType":"purchase_return","entityId":"r1",'
          '"before":null,"after":{"effect":-2000,"reason":"تالف"},'
          '"createdAt":"2026-10-21T10:00:00.000Z"}]}';
      final controller = FinanceController(
        api: _api((r) async => http.Response('{"data":$logsJson}', 200,
            headers: {'content-type': 'application/json'})),
      )..setShop('s1');

      await controller.loadAuditLogs();

      expect(controller.auditLogs, hasLength(1));
      expect(controller.auditLogs.first.action, 'purchase.return');
      expect(controller.auditLogs.first.after?['reason'], 'تالف');
    });

    test('PurchaseReturn و FinancialAdjustment يفسّران القيم النصية', () {
      final ret = PurchaseReturn.fromJson({
        'id': 'r1',
        'shopId': 's1',
        'customerId': 'c1',
        'purchaseId': 'p1',
        'amount': '2000',
        'reason': null,
        'occurredAt': '2026-10-21T10:00:00.000Z',
        'balanceAfter': '5000',
      });
      expect(ret.amount, 2000);
      expect(ret.balanceAfter, 5000);

      final adj = FinancialAdjustment.fromJson({
        'id': 'a1',
        'shopId': 's1',
        'customerId': 'c1',
        'relatedPurchaseId': 'p1',
        'kind': 'cancellation',
        'amount': '-5000',
        'reason': 'إلغاء',
        'occurredAt': '2026-10-21T10:00:00.000Z',
        'balanceAfter': '0',
      });
      expect(adj.isCancellation, isTrue);
      expect(adj.amount, -5000);
    });
  });
}

import 'package:flutter/foundation.dart';

import '../../core/api_exception.dart';
import '../../data/remote/api_client.dart';
import '../../domain/entities/models.dart';

/// يدير المرتجعات والتصحيحات المالية والإلغاءات وسجل التدقيق للمحل النشط.
class FinanceController extends ChangeNotifier {
  FinanceController({required ApiClient api}) : _api = api;

  final ApiClient _api;

  List<PurchaseReturn> _returns = const [];
  List<FinancialAdjustment> _adjustments = const [];
  List<AuditEntry> _auditLogs = const [];
  bool _loading = false;
  String? _error;
  String? _shopId;

  List<PurchaseReturn> get returns => _returns;
  List<FinancialAdjustment> get adjustments => _adjustments;
  List<AuditEntry> get auditLogs => _auditLogs;
  bool get loading => _loading;
  String? get error => _error;

  void setShop(String? shopId) {
    if (_shopId == shopId) return;
    _shopId = shopId;
    _returns = const [];
    _adjustments = const [];
    _auditLogs = const [];
    _error = null;
    notifyListeners();
  }

  /// تحميل المرتجعات (اختياريًا لعميل محدَّد).
  Future<void> loadReturns({String? customerId}) async {
    if (_shopId == null) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _returns = await _api.listReturns(_shopId!, customerId: customerId);
    } on ApiException catch (e) {
      _error = e.message;
      _returns = const [];
    } catch (_) {
      _error = 'تعذر تحميل المرتجعات.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// تسجيل مرتجع — تعيد المرتجع عند النجاح أو null مع رسالة الخطأ.
  Future<({PurchaseReturn? returnEntry, String? error})> addReturn({
    required String purchaseId,
    required int amount,
    String? reason,
    String? id,
    String? idempotencyKey,
  }) async {
    if (_shopId == null) return (returnEntry: null, error: 'لا يوجد محل نشط.');
    try {
      final created = await _api.createReturn(
        _shopId!,
        purchaseId: purchaseId,
        amount: amount,
        reason: reason,
        id: id,
        idempotencyKey: idempotencyKey,
      );
      _returns = [created, ..._returns];
      notifyListeners();
      return (returnEntry: created, error: null);
    } on ApiException catch (e) {
      return (returnEntry: null, error: e.message);
    } catch (_) {
      return (returnEntry: null, error: 'تعذر تسجيل المرتجع.');
    }
  }

  /// تحميل التصحيحات والإلغاءات (اختياريًا لعميل محدَّد).
  Future<void> loadAdjustments({String? customerId}) async {
    if (_shopId == null) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _adjustments = await _api.listAdjustments(_shopId!, customerId: customerId);
    } on ApiException catch (e) {
      _error = e.message;
      _adjustments = const [];
    } catch (_) {
      _error = 'تعذر تحميل التصحيحات.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// تسجيل تصحيح مالي (مبلغ موقّع + سبب إلزامي).
  Future<({FinancialAdjustment? adjustment, String? error})> addAdjustment({
    required String customerId,
    required int amount,
    required String reason,
    String? relatedPurchaseId,
    String? id,
    String? idempotencyKey,
  }) async {
    if (_shopId == null) return (adjustment: null, error: 'لا يوجد محل نشط.');
    try {
      final created = await _api.createAdjustment(
        _shopId!,
        customerId: customerId,
        amount: amount,
        reason: reason,
        relatedPurchaseId: relatedPurchaseId,
        id: id,
        idempotencyKey: idempotencyKey,
      );
      _adjustments = [created, ..._adjustments];
      notifyListeners();
      return (adjustment: created, error: null);
    } on ApiException catch (e) {
      return (adjustment: null, error: e.message);
    } catch (_) {
      return (adjustment: null, error: 'تعذر تسجيل التصحيح.');
    }
  }

  /// إلغاء عملية شراء (قيد عكسي موثق).
  Future<({FinancialAdjustment? adjustment, String? error})> cancelPurchase({
    required String purchaseId,
    required String reason,
    required int version,
    String? id,
    String? idempotencyKey,
  }) async {
    if (_shopId == null) return (adjustment: null, error: 'لا يوجد محل نشط.');
    try {
      final created = await _api.cancelPurchase(
        _shopId!,
        purchaseId,
        reason: reason,
        id: id,
        idempotencyKey: idempotencyKey,
        version: version,
      );
      _adjustments = [created, ..._adjustments];
      notifyListeners();
      return (adjustment: created, error: null);
    } on ApiException catch (e) {
      if (e.isConflict) {
        // تعارض: تم تعديل العملية من قبل مستخدم آخر.
        return (adjustment: null, error: 'تعارض: تم تعديل العملية من جهاز آخر. يرجى تحديث البيانات والمحاولة مرة أخرى.');
      }
      return (adjustment: null, error: e.message);
    } catch (_) {
      return (adjustment: null, error: 'تعذر إلغاء العملية.');
    }
  }

  /// تحميل سجل التدقيق.
  Future<void> loadAuditLogs({String? entityType, String? entityId, String? action}) async {
    if (_shopId == null) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _auditLogs = await _api.listAuditLogs(
        _shopId!,
        entityType: entityType,
        entityId: entityId,
        action: action,
      );
    } on ApiException catch (e) {
      _error = e.message;
      _auditLogs = const [];
    } catch (_) {
      _error = 'تعذر تحميل سجل التدقيق.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}

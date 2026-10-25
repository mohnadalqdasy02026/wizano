import 'package:flutter/foundation.dart';

import '../../data/local/local_store.dart';
import '../../data/repositories/offline_first_repository.dart';
import '../../domain/entities/models.dart';

/// يدير مشتريات المحل النشط: التحميل، التصفية بالعميل، والإضافة.
///
/// يعمل «أولًا محليًا»: إن تعذّر الوصول للخادم، تُحفظ العملية في الطابور المحلي
/// وتظهر بوسم صريح «محلي — غير متزامن» (ولا تُعرض كمعتمدة).
class PurchaseController extends ChangeNotifier {
  PurchaseController({required OfflineFirstRepository repository})
      : _repository = repository;

  final OfflineFirstRepository _repository;

  List<Purchase> _purchases = const [];
  bool _loading = false;
  bool _fromServer = false;
  String? _error;
  String? _shopId;
  int _pendingCount = 0;

  List<Purchase> get purchases => _purchases;
  bool get loading => _loading;
  String? get error => _error;

  /// هل القائمة جُلبت من الخادم (وليس من النسخة المحلية فقط)؟
  ///
  /// إن كانت `false` فالأرقام المعروضة **ناقصة** (عمليات محلية فقط)، فلا
  /// يصحّ عرضها كإجمالي الديون.
  bool get fromServer => _fromServer;

  /// عدد العمليات المحلية غير المرسلة.
  int get pendingCount => _pendingCount;

  void setShop(String? shopId) {
    if (_shopId == shopId) return;
    _shopId = shopId;
    _purchases = const [];
    _error = null;
    notifyListeners();
  }

  Future<void> load({String? customerId}) async {
    if (_shopId == null) return;
    final shopId = _shopId!;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      // محاولة إفراغ الطابور المحلي أولًا (ترفع وسم «غير متزامن» عند النجاح).
      await _repository.syncPending(shopId);
      final remote = await _repository.listRemote(shopId, customerId: customerId);
      final local = await _repository.listLocal(shopId, customerId: customerId);
      _purchases = [...local, ...remote];
      _pendingCount = await _repository.pendingCount(shopId);
      _fromServer = true;
    } catch (_) {
      // دون اتصال: نعرض النسخة المحلية فقط (الأرقام ناقصة).
      try {
        _purchases = await _repository.listLocal(shopId, customerId: customerId);
        _pendingCount = await _repository.pendingCount(shopId);
        _error = null;
        _fromServer = false;
      } catch (_) {
        _error = 'تعذر تحميل المشتريات.';
        _purchases = const [];
        _fromServer = false;
      }
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// تسجيل عملية شراء — تُحفظ محليًا عند انقطاع الشبكة.
  Future<({Purchase? purchase, String? error, bool savedLocally})> add({
    required String customerId,
    required String itemsText,
    required int totalAmount,
    int paidAmount = 0,
    String? notes,
    String? id,
    String? idempotencyKey,
  }) async {
    if (_shopId == null) {
      return (purchase: null, error: 'لا يوجد محل نشط.', savedLocally: false);
    }
    final outcome = await _repository.createPurchase(
      shopId: _shopId!,
      customerId: customerId,
      itemsText: itemsText,
      totalAmount: totalAmount,
      paidAmount: paidAmount,
      notes: notes,
      id: id,
      idempotencyKey: idempotencyKey,
    );
    if (outcome.value == null) {
      return (purchase: null, error: outcome.error, savedLocally: false);
    }
    _purchases = [outcome.value!, ..._purchases];
    if (outcome.savedLocally) {
      _pendingCount = await _repository.pendingCount(_shopId!);
    }
    notifyListeners();
    return (
      purchase: outcome.value,
      error: null,
      savedLocally: outcome.savedLocally,
    );
  }

/// الحصول على عملية واحدة بالمعرّف.
  Future<Purchase?> getPurchase(String purchaseId) async {
    if (_shopId == null) return null;
    try {
      return await _repository.getPurchase(_shopId!, purchaseId);
    } catch (_) {
      return null;
    }
  }

  /// العمليات المحلية غير المرسلة (تفاصيل الطابور).
  Future<List<QueuedOperation>> pendingOperations() async {
    if (_shopId == null) return const [];
    return _repository.pending(_shopId!);
  }
}




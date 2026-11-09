import 'package:flutter/foundation.dart';

import '../../data/local/local_store.dart';
import '../../data/repositories/offline_first_repository.dart';
import '../../domain/entities/models.dart';

/// يدير دفعات المحل النشط: التحميل، التصفية بالعميل، والإضافة.
///
/// تعمل «أولًا محليًا»: إن تعذّر الوصول للخادم، تُحفظ الدفعة محليًا
/// وتظهر بوسم صريح «محلي — غير متزامن».
class PaymentController extends ChangeNotifier {
  PaymentController({required OfflineFirstRepository repository})
      : _repository = repository;

  final OfflineFirstRepository _repository;

  List<Payment> _payments = const [];
  bool _loading = false;
  bool _fromServer = false;
  String? _error;
  String? _shopId;
  int _pendingCount = 0;

  List<Payment> get payments => _payments;
  bool get loading => _loading;
  String? get error => _error;

  /// هل جُلبت القائمة من الخادم (وليس من النسخة المحلية فقط)؟
  ///
  /// إجمالي الديون = مشتريات − مدفوعات، فإذا كانت المدفوعات من الكاش فقد
  /// يكون الرقم ناقصًا. نعرض «—» بدل رقم مضلِّل حتى تتأكد النسخة من الخادم.
  bool get fromServer => _fromServer;

  /// عدد العمليات المحلية غير المرسلة.
  int get pendingCount => _pendingCount;

  void setShop(String? shopId) {
    if (_shopId == shopId) return;
    _shopId = shopId;
    _payments = const [];
    _fromServer = false;
    _error = null;
    notifyListeners();
  }

  /// [silent] تحديث خلفي صامت: لا مؤشر تحميل ولا رسالة خطأ، ويُبقي ما هو
  /// معروض على الشاشة إن تعذّر الوصول.
  Future<void> load({String? customerId, bool silent = false}) async {
    if (_shopId == null) return;
    final shopId = _shopId!;
    if (!silent) {
      _loading = true;
      _error = null;
      notifyListeners();
      try {
        // اعرض النسخة المحفوظة فورًا قبل انتظار الشبكة.
        await _showCached(shopId, customerId: customerId);
        notifyListeners();
      } catch (_) {
        // لا شيء معروض بعد؛ نكمل إلى الجلب من الشبكة.
      }
    }
    try {
      // محاولة إفراغ الطابور المحلي أولًا (ترفع وسم «غير متزامن» عند النجاح).
      await _repository.syncPending(shopId);
      final remote =
          await _repository.listRemotePayments(shopId, customerId: customerId);
      final local =
          await _repository.listLocalPayments(shopId, customerId: customerId);
      _payments = [...local, ...remote.items];
      _pendingCount = await _repository.pendingCount(shopId);
      // في التحديث الصامت لا نقلب الحالة إلى «غير معروفة» بسبب تعثّر لحظي.
      if (!silent || !remote.fromCache) {
        _fromServer = !remote.fromCache;
      }
      _error = null;
    } catch (_) {
      if (!silent) {
        try {
          final local =
              await _repository.listLocalPayments(shopId, customerId: customerId);
          if (local.isNotEmpty) {
            _payments = [...local, ..._payments.where((p) => !local.any((l) => l.id == p.id))];
          }
          _pendingCount = await _repository.pendingCount(shopId);
          _error = null;
          if (!silent) _fromServer = false;
        } catch (_) {
          _error = 'تعذر تحميل المدفوعات.';
          _payments = const [];
          if (!silent) _fromServer = false;
        }
      }
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// يعرض الكاش المحلي فورًا (نسخة الخادم + العمليات غير المرسلة).
  Future<void> _showCached(String shopId, {String? customerId}) async {
    final cached = await _repository.cachedPayments(
      shopId,
      customerId: customerId,
    );
    final local = await _repository.listLocalPayments(
      shopId,
      customerId: customerId,
    );
    if (cached.isEmpty && local.isEmpty) return;
    _payments = [...local, ...cached];
    _fromServer = false;
  }

  /// تسجيل دفعة — تُحفظ محليًا عند انقطاع الشبكة.
  Future<({Payment? payment, String? error, bool savedLocally})> add({
    required String customerId,
    required int amount,
    String? purchaseId,
    String? notes,
    String? id,
    String? idempotencyKey,
  }) async {
    if (_shopId == null) {
      return (payment: null, error: 'لا يوجد محل نشط.', savedLocally: false);
    }
    final outcome = await _repository.createPayment(
      shopId: _shopId!,
      customerId: customerId,
      amount: amount,
      purchaseId: purchaseId,
      notes: notes,
      id: id,
      idempotencyKey: idempotencyKey,
    );
    if (outcome.value == null) {
      return (payment: null, error: outcome.error, savedLocally: false);
    }
    _payments = [outcome.value!, ..._payments];
    if (outcome.savedLocally) {
      _pendingCount = await _repository.pendingCount(_shopId!);
    }
    notifyListeners();
    return (
      payment: outcome.value,
      error: null,
      savedLocally: outcome.savedLocally,
    );
  }

  /// العمليات المحلية غير المرسلة (تفاصيل الطابور).
  Future<List<QueuedOperation>> pendingOperations() async {
    if (_shopId == null) return const [];
    return _repository.pending(_shopId!);
  }
}



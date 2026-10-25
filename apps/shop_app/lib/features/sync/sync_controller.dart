import 'package:flutter/foundation.dart';

import '../../data/local/local_store.dart';
import '../../data/repositories/offline_first_repository.dart';
import '../../domain/entities/sync_status.dart';

/// يدير حالة المزامنة: الطابور المحلي، المتعثر، الناجح، وآخر محاولة.
class SyncController extends ChangeNotifier {
  SyncController({required OfflineFirstRepository repository})
      : _repository = repository;

  final OfflineFirstRepository _repository;

  List<QueuedOperation> _pending = const [];
  List<SyncAttempt> _attempts = const [];
  bool _syncing = false;
  bool _loading = false;
  String? _error;
  String? _shopId;
  String? _retryingId;
  DateTime? _lastSyncAt;

  /// العمليات المحلية غير المُرسلة.
  List<QueuedOperation> get pending => _pending;

  /// آخر محاولات المزامنة.
  List<SyncAttempt> get attempts => _attempts;

  bool get syncing => _syncing;
  bool get loading => _loading;
  String? get error => _error;

  /// معرّف العملية التي تُعاد محاولتها الآن (إن وُجدت).
  String? get retryingId => _retryingId;

  /// عدد العمليات التي لم تُرسل بعد.
  int get pendingCount => _pending.length;

  /// عدد العمليات التي تعذّر إرسالها (تحتاج تدخلًا).
  int get stuckCount =>
      _pending.where((o) => o.status == SyncStatus.failed).length;

  /// آخر مرة أُجرت فيها مزامنة.
  DateTime? get lastSyncAt => _lastSyncAt;

  /// المحل النشط الذي تخصّه المزامنة.
  String? get shopId => _shopId;

  void setShop(String? shopId) {
    if (_shopId == shopId) return;
    _shopId = shopId;
    _pending = const [];
    _attempts = const [];
    _error = null;
    notifyListeners();
  }

  /// يقرأ الطابور وسجل المزامنة.
  Future<void> load() async {
    final shopId = _shopId;
    if (shopId == null) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _pending = await _repository.pending(shopId);
      _attempts = await _repository.syncLog(shopId);
    } catch (_) {
      _error = 'تعذّر قراءة حالة المزامنة.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// إعادة محاولة يدوية لعملية واحدة.
  Future<void> retry(String opId) async {
    if (_retryingId != null) return;
    _retryingId = opId;
    _error = null;
    notifyListeners();
    String? message;
    try {
      final result = await _repository.retryOperation(opId);
      if (result == SyncAttemptStatus.offline) {
        message = 'تعذّر الوصول إلى الخادم — العملية ما زالت في الطابور.';
      } else if (result == SyncAttemptStatus.failed) {
        message = 'رفض الخادم العملية — راجع السبب في القائمة.';
      }
    } catch (_) {
      message = 'تعذّر تنفيذ إعادة المحاولة.';
    } finally {
      _retryingId = null;
    }
    await load();
    // رسالة النتيجة لا تُمسح عند نجاح إعادة القراءة.
    if (message != null && _error == null) {
      _error = message;
      notifyListeners();
    }
  }

  /// محاولة إرسال كل العمليات المعلّقة.
  Future<void> syncNow() async {
    final shopId = _shopId;
    if (shopId == null || _syncing) return;
    _syncing = true;
    _error = null;
    notifyListeners();
    String? message;
    try {
      final report = await _repository.syncPending(shopId);
      _lastSyncAt = DateTime.now();
      if (report.offline) {
        message = 'تعذّر الوصول إلى الخادم — ستبقى العمليات في الطابور.';
      }
    } catch (_) {
      message = 'تعذّر تنفيذ المزامنة.';
    } finally {
      _syncing = false;
    }
    await load();
    // رسالة المزامنة لا تُمسح عند نجاح إعادة القراءة.
    if (message != null && _error == null) {
      _error = message;
      notifyListeners();
    }
  }
}


import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../../core/api_exception.dart';
import '../../core/connectivity.dart';
import '../../data/local/local_store.dart';
import '../../data/remote/api_client.dart';
import '../../domain/entities/models.dart';
import '../../domain/entities/sync_status.dart';

/// نتيجة محاولة تسجيل عملية: نجحت على الخادم، أو حُفظت محليًا.
class OperationOutcome<T> {
  final T? value;
  final String? error;

  /// هل حُفظت العملية محليًا في انتظار المزامنة؟
  final bool savedLocally;

  const OperationOutcome.success(this.value)
      : error = null,
        savedLocally = false;

  const OperationOutcome.local(this.value)
      : error = null,
        savedLocally = true;

  const OperationOutcome.failure(this.error)
      : value = null,
        savedLocally = false;
}

/// نتيجة محاولة إفراغ الطابور المحلي.
class SyncReport {
  /// عدد العمليات التي اعتمدها الخادم.
  final int sent;

  /// عدد العمليات التي رفضها الخادم (تحتاج مراجعة).
  final int failed;

  /// عدد العمليات التي لم تُرسل بعد.
  final int remaining;

  /// هل تعذّر الوصول إلى الخادم؟
  final bool offline;

  const SyncReport({
    this.sent = 0,
    this.failed = 0,
    this.remaining = 0,
    this.offline = false,
  });
}

/// مستودع «يعمل أولاً محليًا»: يحاول الإرسال للخادم، وعند فشل الشبكة
/// يحفظ العملية في الطابور المحلي مع وسم صريح (غير متزامن).
///
/// **قاعدة:** أي عملية محفوظة محليًا لا تُعرض كأنها معتمدة مركزيًا.
class OfflineFirstRepository {
  OfflineFirstRepository({
    required ApiClient api,
    required LocalStore queue,
    Uuid? uuid,
    ConnectivityMonitor? monitor,
    FlutterSecureStorage? remoteCache,
  })  : _api = api,
        _queue = queue,
        _uuid = uuid ?? const Uuid(),
        _monitor = monitor,
        _remoteCache = remoteCache ?? const FlutterSecureStorage();

  final ApiClient _api;
  final LocalStore _queue;
  final Uuid _uuid;

  /// مراقب حالة الاتصال (اختياري) — يُحدَّث بنتيجة كل طلب.
  final ConnectivityMonitor? _monitor;
  final FlutterSecureStorage _remoteCache;

  LocalStore get queue => _queue;

  String _purchasesCacheKey(String shopId) =>
      'wizano.shop.cache.purchases.$shopId';
  String _paymentsCacheKey(String shopId) =>
      'wizano.shop.cache.payments.$shopId';

  /// هل الخطأ خطأ شبكة (يستحق الحفظ المحلي) أم خطأ منطقي (رفض الخادم)؟
  static bool _isNetworkFailure(Object error) =>
      error is ApiException && error.code == 'NETWORK_ERROR';

  /// هل الخطأ خطأ مؤقت في الخادم (5xx) يُعاد المحاولة عليه لاحقًا؟
  static bool _isTransientServerError(Object error) =>
      error is ApiException &&
      (error.statusCode ?? 0) >= 500;

  /// يحدّث مراقب الاتصال بنتيجة الطلب.
  void _report(Object? error) {
    final monitor = _monitor;
    if (monitor == null) return;
    if (error == null) {
      monitor.reportOnline();
    } else if (_isNetworkFailure(error)) {
      monitor.reportOffline();
    }
  }

  /// يسجّل عملية شراء: على الخادم، أو محليًا عند انقطاع الشبكة.
  Future<OperationOutcome<Purchase>> createPurchase({
    required String shopId,
    required String customerId,
    required String itemsText,
    required int totalAmount,
    int paidAmount = 0,
    String? notes,
    String? id,
    String? idempotencyKey,
  }) async {
    final localId = id ?? _uuid.v7();
    final key = idempotencyKey ?? _uuid.v7();
    final payload = {
      'id': localId,
      'customerId': customerId,
      'itemsText': itemsText,
      'totalAmount': totalAmount,
      'paidAmount': paidAmount,
      'notes': notes,
      'idempotencyKey': key,
    };
    try {
      final created = await _api.createPurchase(
        shopId,
        customerId: customerId,
        itemsText: itemsText,
        totalAmount: totalAmount,
        paidAmount: paidAmount,
        notes: notes,
        id: localId,
        idempotencyKey: key,
      );
      _report(null);
      return OperationOutcome.success(created);
    } catch (error) {
      _report(error);
      if (!_isNetworkFailure(error)) {
        return OperationOutcome.failure(
          error is ApiException ? error.message : 'تعذر تسجيل العملية.',
        );
      }
      await _queue.enqueue(
        id: localId,
        opType: LocalOpType.purchase,
        shopId: shopId,
        customerId: customerId,
        idempotencyKey: key,
        payload: payload,
      );
      await _queue.cacheOperation(
        id: localId,
        opType: LocalOpType.purchase,
        shopId: shopId,
        customerId: customerId,
        payload: {
          ...payload,
          'shopId': shopId,
          'occurredAt': DateTime.now().toUtc().toIso8601String(),
        },
      );
      return OperationOutcome.local(_localPurchase(payload, shopId));
    }
  }

  /// يسجّل دفعة: على الخادم، أو محليًا عند انقطاع الشبكة.
  Future<OperationOutcome<Payment>> createPayment({
    required String shopId,
    required String customerId,
    required int amount,
    String? purchaseId,
    String? notes,
    String? id,
    String? idempotencyKey,
  }) async {
    final localId = id ?? _uuid.v7();
    final key = idempotencyKey ?? _uuid.v7();
    final payload = {
      'id': localId,
      'customerId': customerId,
      'amount': amount,
      'purchaseId': purchaseId,
      'notes': notes,
      'idempotencyKey': key,
    };
    try {
      final created = await _api.createPayment(
        shopId,
        customerId: customerId,
        amount: amount,
        purchaseId: purchaseId,
        notes: notes,
        id: localId,
        idempotencyKey: key,
      );
      _report(null);
      return OperationOutcome.success(created);
    } catch (error) {
      _report(error);
      if (!_isNetworkFailure(error)) {
        return OperationOutcome.failure(
          error is ApiException ? error.message : 'تعذر تسجيل الدفعة.',
        );
      }
      await _queue.enqueue(
        id: localId,
        opType: LocalOpType.payment,
        shopId: shopId,
        customerId: customerId,
        idempotencyKey: key,
        payload: payload,
      );
      await _queue.cacheOperation(
        id: localId,
        opType: LocalOpType.payment,
        shopId: shopId,
        customerId: customerId,
        payload: {
          ...payload,
          'shopId': shopId,
          'paidAt': DateTime.now().toUtc().toIso8601String(),
        },
      );
      return OperationOutcome.local(_localPayment(payload, shopId));
    }
  }

  /// عدد العمليات المحلية غير المرسلة لمحل معيّن.
  Future<int> pendingCount(String shopId) =>
      _queue.count(shopId: shopId);

  /// العمليات المحلية غير المرسلة (لعرضها للمستخدم).
  Future<List<QueuedOperation>> pending(String shopId) =>
      _queue.list(shopId: shopId);

  /// آخر محاولات المزامنة (سجل المزامنة).
  Future<List<SyncAttempt>> syncLog(String shopId, {int limit = 50}) =>
      _queue.recentAttempts(shopId: shopId, limit: limit);

  /// عملاء المحل: من الخادم، وإن تعذّر الوصول فمن نسخة محلية محفوظة.
  ///
  /// تُحفظ نسخة العملاء تلقائيًا بعد كل جلب ناجح، ليبقى اختيار العميل
  /// ممكنًا أثناء العمل دون اتصال.
  Future<({List<Customer> customers, bool fromCache})> listCustomers(
    String shopId, {
    String? search,
  }) async {
    try {
      final remote = await _api.listCustomers(shopId, search: search);
      // نحفظ النسخة الكاملة (بلا بحث) ليبقى العرض دون اتصال ممكنًا.
      if ((search ?? '').trim().isEmpty) {
        await _queue.replaceCustomers(shopId, remote);
      }
      _report(null);
      return (customers: remote, fromCache: false);
    } catch (error) {
      _report(error);
      if (!_isNetworkFailure(error)) {
        return (customers: const <Customer>[], fromCache: false);
      }
      final local = await _queue.listCustomers(shopId);
      return (customers: local, fromCache: true);
    }
  }

  /// محلات المستخدم: من الخادم، وإن تعذّر الوصول فمن نسخة محلية محفوظة.
  ///
  /// تُحفظ نسخة المحلات محليًا ليعرف التطبيق محله النشط دون اتصال (وإلا
  /// ظنّ أنه بلا محل وطلب إنشاء محل جديد).
  Future<({List<Shop> shops, bool fromCache})> listShops() async {
    try {
      final remote = await _api.listShops();
      await _queue.replaceShops(remote);
      return (shops: remote, fromCache: false);
    } catch (error) {
      if (!_isNetworkFailure(error)) {
        return (shops: const <Shop>[], fromCache: false);
      }
      final local = await _queue.listShops();
      return (shops: local, fromCache: true);
    }
  }

  /// يحفظ نسخة محلية من العميل (بعد إضافة أو تعديل ناجح).
  Future<void> cacheCustomer(String shopId, Customer customer) async {
    final current = await _queue.listCustomers(shopId);
    final updated = [
      for (final c in current)
        if (c.id == customer.id) customer else c,
      if (!current.any((c) => c.id == customer.id)) customer,
    ];
    await _queue.replaceCustomers(shopId, updated);
  }

  /// إضافة عميل تعمل دون اتصال: يحفظ العميل وطلب إنشائه محليًا ثم يرسله
  /// تلقائيًا عند عودة الشبكة. المعرّف يولد على الهاتف ليبقى مرجع العمليات.
  Future<OperationOutcome<Customer>> createCustomer({
    required String shopId,
    required String displayName,
    String? phone,
    String? notes,
  }) async {
    final id = _uuid.v7();
    final payload = <String, dynamic>{
      'id': id,
      'displayName': displayName,
      if (phone != null) 'phone': phone,
      if (notes != null) 'notes': notes,
    };
    try {
      final customer = await _api.createCustomer(
        shopId,
        id: id,
        displayName: displayName,
        phone: phone,
        notes: notes,
      );
      await cacheCustomer(shopId, customer);
      _report(null);
      return OperationOutcome.success(customer);
    } catch (error) {
      _report(error);
      if (!_isNetworkFailure(error)) {
        return OperationOutcome.failure(
          error is ApiException ? error.message : 'تعذر إضافة العميل.',
        );
      }
      final customer = Customer(
        id: id,
        displayName: displayName,
        phone: phone,
        notes: notes,
      );
      await _queue.enqueue(
        id: id,
        opType: LocalOpType.customer,
        shopId: shopId,
        customerId: id,
        idempotencyKey: id,
        payload: payload,
      );
      await cacheCustomer(shopId, customer);
      return OperationOutcome.local(customer);
    }
  }

  /// أقصى عدد محاولات لعملية واحدة قبل التوقف عن إعادة الإرسال.
  static const int maxAttempts = 5;

  /// مزامنة جارية الآن (لمنع المزامنة المتزامنة لنفس العملية).
  Future<SyncReport>? _syncInFlight;

  /// يفرّغ الطابور المحلي: يرسل العمليات المعلّقة للخادم بالترتيب.
  ///
  /// **لا مزامنة متزامنة:** إن طُلبت المزامنة أثناء 진행 أخرى، تُعاد النتيجة
  /// نفسها (تكرار الإرسال لنفس العملية يسبّب تعارضًا على الخادم).
  Future<SyncReport> syncPending(String shopId) {
    final inFlight = _syncInFlight;
    if (inFlight != null) return inFlight;
    final future = _doSyncPending(shopId);
    _syncInFlight = future;
    return future.whenComplete(() => _syncInFlight = null);
  }

  Future<SyncReport> _doSyncPending(String shopId) async {
    final operations = await _queue.list(shopId: shopId);
    final pending = operations.where((o) => o.status.isPending).toList();
    var sent = 0;
    var failed = 0;

    for (final op in pending) {
      if (op.attempts >= maxAttempts) continue;
      try {
        await _send(op);
        await _queue.remove(op.id);
        await _queue.removeCache(op.id);
        await _queue.logAttempt(
          opId: op.id,
          opType: op.opType,
          shopId: op.shopId,
          status: SyncAttemptStatus.sent,
        );
        _report(null);
        sent++;
      } on ApiException catch (e) {
        if (_isNetworkFailure(e)) {
          // انقطاع الشبكة ليس خطأً في العملية: لا تُحتسب محاولة حتى لا
          // تستنفد العملية حدّ المحاولات بسبب انقطاع مؤقت.
          await _queue.updateStatus(
            op.id,
            SyncStatus.local,
            error: e.message,
          );
          await _queue.logAttempt(
            opId: op.id,
            opType: op.opType,
            shopId: op.shopId,
            status: SyncAttemptStatus.offline,
            message: e.message,
          );
          _report(e);
          return SyncReport(
            sent: sent,
            failed: failed,
            remaining: await _queue.count(shopId: shopId),
            offline: true,
          );
        }
        if (_isTransientServerError(e)) {
          // خطأ مؤقت في الخادم (5xx): العملية سليمة، فتُعاد لاحقًا ولا
          // تُعدّ رفضًا يحتاج تدخل المستخدم.
          await _queue.updateStatus(
            op.id,
            SyncStatus.local,
            error: e.message,
          );
          await _queue.logAttempt(
            opId: op.id,
            opType: op.opType,
            shopId: op.shopId,
            status: SyncAttemptStatus.offline,
            message: e.message,
          );
          continue;
        }
        if (e.isConflict) {
        if (e.isConflict) {
          await _queue.updateStatus(
            op.id,
            SyncStatus.conflict,
            error: e.message,
          );
          await _queue.logAttempt(
            opId: op.id,
            opType: op.opType,
            shopId: op.shopId,
            status: SyncAttemptStatus.failed,
            message: e.message,
          );
          _report(null);
          failed++;
          continue;
        }
        await _queue.updateStatus(
          op.id,
          SyncStatus.failed,
          error: e.message,
          );
          await _queue.logAttempt(
            opId: op.id,
            opType: op.opType,
            shopId: op.shopId,
            status: SyncAttemptStatus.failed,
            message: e.message,
          );
          _report(null);
          failed++;
          continue;
        }
        await _queue.updateStatus(
          op.id,
          SyncStatus.failed,
          incrementAttempts: true,
        );
        await _queue.logAttempt(
          opId: op.id,
          opType: op.opType,
          shopId: op.shopId,
          status: SyncAttemptStatus.failed,
          message: e.message,
        );
        _report(null);
        failed++;
      } catch (_) {
        await _queue.updateStatus(
          op.id,
          SyncStatus.failed,
          error: 'تعذّر إرسال العملية.',
          incrementAttempts: true,
        );
        await _queue.logAttempt(
          opId: op.id,
          opType: op.opType,
          shopId: op.shopId,
          status: SyncAttemptStatus.failed,
          message: 'تعذّر إرسال العملية.',
        );
        failed++;
      }
    }

    return SyncReport(
      sent: sent,
      failed: failed,
      remaining: await _queue.count(shopId: shopId),
    );
  }

  /// إعادة محاولة يدوية لعملية واحدة في الطابور.
  ///
  /// الطلب الصريح من المستخدم يُصفّر عدّاد المحاولات، حتى لا تظل العملية
  /// متوقفة بعد بلوغ الحد الأقصى. لا تُحذف العملية أبدًا عند الفشل.
  Future<SyncAttemptStatus> retryOperation(String id) async {
    final op = await _queue.findOperation(id);
    if (op == null) return SyncAttemptStatus.failed;

    await _queue.updateStatus(op.id, SyncStatus.local, resetAttempts: true);
    try {
      await _send(op);
      await _queue.remove(op.id);
      await _queue.removeCache(op.id);
      await _queue.logAttempt(
        opId: op.id,
        opType: op.opType,
        shopId: op.shopId,
        status: SyncAttemptStatus.sent,
      );
      _report(null);
      return SyncAttemptStatus.sent;
    } on ApiException catch (e) {
      final offline = _isNetworkFailure(e) || _isTransientServerError(e);
      await _queue.updateStatus(
        op.id,
        offline ? SyncStatus.local : SyncStatus.failed,
        error: e.message,
        incrementAttempts: !offline,
      );
      await _queue.logAttempt(
        opId: op.id,
        opType: op.opType,
        shopId: op.shopId,
        status: offline ? SyncAttemptStatus.offline : SyncAttemptStatus.failed,
        message: e.message,
      );
      _report(e);
      return offline ? SyncAttemptStatus.offline : SyncAttemptStatus.failed;
    } catch (_) {
      await _queue.updateStatus(
        op.id,
        SyncStatus.failed,
        error: 'تعذّر إرسال العملية.',
        incrementAttempts: true,
      );
      await _queue.logAttempt(
        opId: op.id,
        opType: op.opType,
        shopId: op.shopId,
        status: SyncAttemptStatus.failed,
        message: 'تعذّر إرسال العملية.',
      );
      return SyncAttemptStatus.failed;
    }
  }

  /// يرسل عملية واحدة من الطابور إلى الخادم.
  Future<void> _send(QueuedOperation op) async {    final payload = op.payload;
    switch (op.opType) {
      case LocalOpType.customer:
        await _api.createCustomer(
          op.shopId,
          id: op.id,
          displayName: payload['displayName']! as String,
          phone: payload['phone'] as String?,
          notes: payload['notes'] as String?,
        );
      case LocalOpType.purchase:
        await _api.createPurchase(
          op.shopId,
          customerId: op.customerId,
          itemsText: payload['itemsText']! as String,
          totalAmount: (payload['totalAmount']! as num).toInt(),
          paidAmount: (payload['paidAmount'] as num?)?.toInt() ?? 0,
          notes: payload['notes'] as String?,
          id: op.id,
          idempotencyKey: op.idempotencyKey,
        );
      case LocalOpType.payment:
        await _api.createPayment(
          op.shopId,
          customerId: op.customerId,
          amount: (payload['amount']! as num).toInt(),
          purchaseId: payload['purchaseId'] as String?,
          notes: payload['notes'] as String?,
          id: op.id,
          idempotencyKey: op.idempotencyKey,
        );
    }
  }


  /// المشتريات المعتمدة على الخادم.
  Future<List<Purchase>> listRemote(String shopId, {String? customerId}) async {
    try {
      final result = await _api.listPurchases(shopId, customerId: customerId);
      // نحتفظ بآخر نسخة مؤكدة من الخادم، لا بالعمليات المعلقة فقط، كي يظهر
      // سجل المشتريات السابق كاملًا عند فتح التطبيق دون إنترنت.
      if (customerId == null) {
        await _remoteCache.write(
          key: _purchasesCacheKey(shopId),
          value: jsonEncode(result.map(_purchaseJson).toList()),
        );
      }
      _report(null);
      return result;
    } catch (error) {
      _report(error);
      final cached = await _readPurchaseCache(shopId, customerId: customerId);
      if (cached.isNotEmpty) return cached;
      rethrow;
    }
  }

  /// المشتريات المحلية المحفوظة (غير المرسلة بعد).
  Future<List<Purchase>> listLocal(String shopId, {String? customerId}) async {
    final rows = await _queue.cachedOperations(
      shopId: shopId,
      customerId: customerId,
    );
    return rows
        .where((r) => r['itemsText'] != null)
        .map(cachedPurchase)
        .toList();
  }

  /// المدفوعات المعتمدة على الخادم.
  Future<List<Payment>> listRemotePayments(
    String shopId, {
    String? customerId,
  }) async {
    try {
      final result = await _api.listPayments(shopId, customerId: customerId);
      if (customerId == null) {
        await _remoteCache.write(
          key: _paymentsCacheKey(shopId),
          value: jsonEncode(result.map(_paymentJson).toList()),
        );
      }
      _report(null);
      return result;
    } catch (error) {
      _report(error);
      final cached = await _readPaymentCache(shopId, customerId: customerId);
      if (cached.isNotEmpty) return cached;
      rethrow;
    }
  }

  Future<List<Purchase>> _readPurchaseCache(
    String shopId, {
    String? customerId,
  }) async {
    try {
      final raw = await _remoteCache.read(key: _purchasesCacheKey(shopId));
      if (raw == null) return const [];
      final rows = jsonDecode(raw) as List<dynamic>;
      final items = rows
          .map((row) => Purchase.fromJson(row as Map<String, dynamic>))
          .toList(growable: false);
      return customerId == null
          ? items
          : items.where((item) => item.customerId == customerId).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<Payment>> _readPaymentCache(
    String shopId, {
    String? customerId,
  }) async {
    try {
      final raw = await _remoteCache.read(key: _paymentsCacheKey(shopId));
      if (raw == null) return const [];
      final rows = jsonDecode(raw) as List<dynamic>;
      final items = rows
          .map((row) => Payment.fromJson(row as Map<String, dynamic>))
          .toList(growable: false);
      return customerId == null
          ? items
          : items.where((item) => item.customerId == customerId).toList();
    } catch (_) {
      return const [];
    }
  }

  Map<String, dynamic> _purchaseJson(Purchase item) => {
        'id': item.id,
        'shopId': item.shopId,
        'customerId': item.customerId,
        'shopSeq': item.shopSeq,
        'occurredAt': item.occurredAt,
        'itemsText': item.itemsText,
        'totalAmount': item.totalAmount,
        'paidAmount': item.paidAmount,
        'remainingAmount': item.remainingAmount,
        'notes': item.notes,
        'status': item.status,
        'statusReason': item.statusReason,
        'balanceAfter': item.balanceAfter,
        'version': item.version,
      };

  Map<String, dynamic> _paymentJson(Payment item) => {
        'id': item.id,
        'shopId': item.shopId,
        'customerId': item.customerId,
        'purchaseId': item.purchaseId,
        'amount': item.amount,
        'paidAt': item.paidAt,
        'shopSeq': item.shopSeq,
        'notes': item.notes,
        'balanceAfter': item.balanceAfter,
      };

  /// المدفوعات المحلية المحفوظة (غير المرسلة بعد).
  Future<List<Payment>> listLocalPayments(
    String shopId, {
    String? customerId,
  }) async {
    final rows = await _queue.cachedOperations(
      shopId: shopId,
      customerId: customerId,
    );
    return rows
        .where((r) => r['amount'] != null && r['itemsText'] == null)
        .map(cachedPayment)
        .toList();
  }

Purchase _localPurchase(Map<String, dynamic> payload, String shopId) {
    final total = (payload['totalAmount'] as num).toInt();
    final paid = (payload['paidAmount'] as num?)?.toInt() ?? 0;
    return Purchase(
      id: payload['id']! as String,
      shopId: shopId,
      customerId: payload['customerId']! as String,
      shopSeq: '—',
      occurredAt: DateTime.now().toUtc().toIso8601String(),
      itemsText: payload['itemsText']! as String,
      totalAmount: total,
      paidAmount: paid,
      remainingAmount: total - paid,
      notes: payload['notes'] as String?,
      status: 'active',
      syncStatus: SyncStatus.local,
      version: 1,
    );
  }

  Payment _localPayment(Map<String, dynamic> payload, String shopId) {
    return Payment(
      id: payload['id']! as String,
      shopId: shopId,
      customerId: payload['customerId']! as String,
      purchaseId: payload['purchaseId'] as String?,
      amount: (payload['amount'] as num).toInt(),
      paidAt: DateTime.now().toUtc().toIso8601String(),
      notes: payload['notes'] as String?,
      syncStatus: SyncStatus.local,
    );
  }

  /// يحوّل نسخة محلية مخزَّنة إلى نموذج Purchase (للعرض أثناء انقطاع الشبكة).
static Purchase cachedPurchase(Map<String, dynamic> json) {
    final total = (json['totalAmount'] as num).toInt();
    final paid = (json['paidAmount'] as num?)?.toInt() ?? 0;
    return Purchase(
      id: json['id']! as String,
      shopId: json['shopId']! as String,
      customerId: json['customerId']! as String,
      shopSeq: '—',
      occurredAt: json['occurredAt'] as String? ??
          DateTime.now().toUtc().toIso8601String(),
      itemsText: json['itemsText']! as String,
      totalAmount: total,
      paidAmount: paid,
      remainingAmount: total - paid,
      notes: json['notes'] as String?,
      status: 'active',
      syncStatus: SyncStatus.local,
      version: (json['version'] as num?)?.toInt() ?? 1,
    );
  }

  /// يحوّل نسخة محلية مخزَّنة إلى نموذج Payment.
  static Payment cachedPayment(Map<String, dynamic> json) {
    return Payment(
      id: json['id']! as String,
      shopId: json['shopId']! as String,
      customerId: json['customerId']! as String,
      purchaseId: json['purchaseId'] as String?,
      amount: (json['amount'] as num).toInt(),
      paidAt: json['paidAt'] as String? ??
          DateTime.now().toUtc().toIso8601String(),
      notes: json['notes'] as String?,
      syncStatus: SyncStatus.local,
    );
  }

/// يقرأ نص JSON من الطابور (للاختبار والتشخيص).
  static String encodePayload(Map<String, dynamic> payload) =>
      jsonEncode(payload);

  /// يحصل على عملية واحدة بالمعرّف (محليًا أو من الخادم).
  Future<Purchase?> getPurchase(String shopId, String purchaseId) async {
    try {
      // نحاول أولاً من الخادم.
      final remote = await _api.getPurchase(shopId, purchaseId);
      return remote;
    } catch (_) {
      // دون اتصال: نبحث في النسخة المحلية.
      final local = await _queue.cachedOperations(
        shopId: shopId,
      );
      final row = local.firstWhere(
        (r) => r['id'] == purchaseId && r['itemsText'] != null,
        orElse: () => <String, dynamic>{},
      );
      if (row.isEmpty) return null;
      // Ensure shopId is in the row for cachedPurchase
      final rowWithShop = {...row, 'shopId': shopId};
      return cachedPurchase(rowWithShop);
    }
  }

}




import 'package:shop_app/data/local/local_store.dart';
import 'package:shop_app/domain/entities/models.dart';
import 'package:shop_app/domain/entities/sync_status.dart';

/// مخزن طابور في الذاكرة — للاختبارات (لا يعتمد على SQLite).
class InMemoryLocalStore implements LocalStore {
  final List<QueuedOperation> _operations = [];
  final List<Map<String, dynamic>> _cache = [];
  final List<SyncAttempt> _attempts = [];
  final List<_CachedCustomer> _customers = [];
  final List<Shop> _shops = [];

  List<QueuedOperation> get operations => List.unmodifiable(_operations);
  List<Map<String, dynamic>> get cache => List.unmodifiable(_cache);
  List<SyncAttempt> get attempts => List.unmodifiable(_attempts);

  @override
  Future<List<QueuedOperation>> list({String? shopId, SyncStatus? status}) async {
    return _operations
        .where((o) => shopId == null || o.shopId == shopId)
        .where((o) => status == null || o.status == status)
        .toList();
  }

  @override
  Future<int> count({String? shopId}) async => (await list(shopId: shopId)).length;

  @override
  Future<void> enqueue({
    required String id,
    required LocalOpType opType,
    required String shopId,
    required String customerId,
    required String idempotencyKey,
    required Map<String, dynamic> payload,
  }) async {
    final existing = _operations.where((o) => o.id == id);
    if (existing.isNotEmpty) {
      final index = _operations.indexOf(existing.first);
      _operations[index] = QueuedOperation(
        id: id,
        opType: opType,
        shopId: shopId,
        customerId: customerId,
        idempotencyKey: idempotencyKey,
        payload: payload,
        status: SyncStatus.local,
        attempts: existing.first.attempts,
        lastError: null,
        createdAt: existing.first.createdAt,
        updatedAt: DateTime.now(),
      );
      return;
    }
    final now = DateTime.now();
    _operations.add(QueuedOperation(
      id: id,
      opType: opType,
      shopId: shopId,
      customerId: customerId,
      idempotencyKey: idempotencyKey,
      payload: payload,
      status: SyncStatus.local,
      attempts: 0,
      lastError: null,
      createdAt: now,
      updatedAt: now,
    ));
  }

  @override
  Future<void> updateStatus(
    String id,
    SyncStatus status, {
    String? error,
    bool incrementAttempts = false,
    bool resetAttempts = false,
  }) async {
    final index = _operations.indexWhere((o) => o.id == id);
    if (index < 0) return;
    final o = _operations[index];
    _operations[index] = QueuedOperation(
      id: o.id,
      opType: o.opType,
      shopId: o.shopId,
      customerId: o.customerId,
      idempotencyKey: o.idempotencyKey,
      payload: o.payload,
      status: status,
      attempts: resetAttempts
          ? 0
          : (incrementAttempts ? o.attempts + 1 : o.attempts),
      lastError: error,
      createdAt: o.createdAt,
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<QueuedOperation?> findOperation(String id) async {
    for (final o in _operations) {
      if (o.id == id) return o;
    }
    return null;
  }

  @override
  Future<void> remove(String id) async {
    _operations.removeWhere((o) => o.id == id);
  }

  @override
  Future<void> clearShop(String shopId) async {
    _operations.removeWhere((o) => o.shopId == shopId);
  }

  @override
  Future<void> cacheOperation({
    required String id,
    required LocalOpType opType,
    required String shopId,
    required String customerId,
    required Map<String, dynamic> payload,
  }) async {
    _cache.removeWhere((c) => c['id'] == id);
    _cache.insert(0, {'id': id, ...payload});
  }

  @override
  Future<List<Map<String, dynamic>>> cachedOperations({
    String? shopId,
    String? customerId,
  }) async {
    return _cache
        .where((c) => shopId == null || c['shopId'] == shopId)
        .where((c) => customerId == null || c['customerId'] == customerId)
        .toList();
  }

  @override
  Future<void> removeCache(String id) async {
    _cache.removeWhere((c) => c['id'] == id);
  }

  @override
  Future<void> logAttempt({
    required String opId,
    required LocalOpType opType,
    required String shopId,
    required SyncAttemptStatus status,
    String? message,
  }) async {
    _attempts.insert(0, SyncAttempt(
      id: _attempts.length + 1,
      opId: opId,
      opType: opType,
      shopId: shopId,
      status: status,
      message: message,
      createdAt: DateTime.now(),
    ));
  }

  @override
  Future<List<SyncAttempt>> recentAttempts({
    String? shopId,
    int limit = 50,
  }) async {
    return _attempts
        .where((a) => shopId == null || a.shopId == shopId)
        .take(limit)
        .toList();
  }

  @override
  Future<void> replaceCustomers(String shopId, List<Customer> customers) async {
    _customers
      ..removeWhere((c) => c.shopId == shopId)
      ..addAll(customers.map((c) => _CachedCustomer(shopId: shopId, customer: c)));
  }

  @override
  Future<List<Customer>> listCustomers(String shopId) async {
    return _customers
        .where((c) => c.shopId == shopId)
        .map((c) => c.customer)
        .toList();
  }

  @override
  Future<void> replaceShops(List<Shop> shops) async {
    _shops
      ..clear()
      ..addAll(shops);
  }

  @override
  Future<List<Shop>> listShops() async => List.unmodifiable(_shops);
}

class _CachedCustomer {
  const _CachedCustomer({required this.shopId, required this.customer});

  final String shopId;
  final Customer customer;
}


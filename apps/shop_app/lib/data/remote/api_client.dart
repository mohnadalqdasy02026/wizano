import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../core/api_exception.dart';
import '../../core/token_store.dart';
import '../../domain/entities/models.dart';

/// حالة الخادم بعد فحص الاتصال.
enum ServerStatus { ok, degraded, offline }

class HealthResult {
  const HealthResult(this.status, this.message);

  final ServerStatus status;
  final String message;

  bool get isReachable => status != ServerStatus.offline;
}

/// عميل API المركزي: فحص الصحة، المصادقة، والمحلات.
///
/// - يحوّل أخطاء الخادم إلى [ApiException] برسالة عربية.
/// - يضيف ترويسة Bearer تلقائيًا من [TokenStore].
/// - عند 401 يحاول تجديد الرمز مرة واحدة عبر رمز التجديد، ثم يعيد المحاولة.
class ApiClient {
  ApiClient({
    required TokenStore tokenStore,
    http.Client? httpClient,
    String? baseUrl,
  })  : _tokens = tokenStore,
        _http = httpClient ?? http.Client(),
        baseUrl = baseUrl ??
            const String.fromEnvironment(
              'API_BASE_URL',
              defaultValue: 'http://127.0.0.1:4000',
            );

  final TokenStore _tokens;
  final http.Client _http;
  final String baseUrl;

  static const Duration _timeout = Duration(seconds: 8);

  Uri _uri(String path) => Uri.parse('$baseUrl/api/v1$path');

  Map<String, String> _headers(String? accessToken, {bool withBody = true}) => {
        if (withBody) 'content-type': 'application/json',
        if (accessToken != null) 'authorization': 'Bearer $accessToken',
      };

  // ---------------------------------------------------------------------------
  // الصحة
  // ---------------------------------------------------------------------------

  Future<HealthResult> getHealth() async {
    try {
      final response = await _http.get(_uri('/health')).timeout(_timeout);
      if (response.statusCode != 200) {
        return HealthResult(
          ServerStatus.offline,
          'رد غير متوقع من الخادم (رمز ${response.statusCode}).',
        );
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final data = body['data'] as Map<String, dynamic>?;
      if (data?['status'] == 'ok' && data?['db'] == 'up') {
        return const HealthResult(
          ServerStatus.ok,
          'متصل بالخادم، وقاعدة البيانات تعمل.',
        );
      }
      return const HealthResult(
        ServerStatus.degraded,
        'الخادم يستجيب لكن قاعدة البيانات غير متاحة.',
      );
    } catch (_) {
      return const HealthResult(
        ServerStatus.offline,
        'تعذر الوصول إلى الخادم. تحقق من اتصال الشبكة وعنوان الخادم.',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // المصادقة
  // ---------------------------------------------------------------------------

  Future<AuthSession> register({
    required String displayName,
    required String email,
    required String password,
  }) async {
    final data = await _send(
      method: 'POST',
      path: '/auth/register',
      body: {'displayName': displayName, 'email': email, 'password': password},
    );
    return AuthSession.fromJson(data);
  }

  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    final data = await _send(
      method: 'POST',
      path: '/auth/login',
      body: {'email': email, 'password': password},
    );
    return AuthSession.fromJson(data);
  }

  Future<User> me() async {
    final data = await _send(method: 'GET', path: '/me');
    return User.fromJson(data['user'] as Map<String, dynamic>);
  }

  Future<void> logout() async {
    final refresh = await _tokens.readRefreshToken();
    if (refresh == null) return;
    try {
      final access = await _tokens.readAccessToken();
      await _http
          .post(
            _uri('/auth/logout'),
            headers: _headers(access),
            body: jsonEncode({'refreshToken': refresh}),
          )
          .timeout(_timeout);
    } catch (_) {
      // الخروج محليًا دائمًا ينجح حتى لو فشل الاستدعاء الشبكي.
    }
  }

  // ---------------------------------------------------------------------------
  // المحلات
  // ---------------------------------------------------------------------------

  Future<List<Shop>> listShops() async {
    final data = await _send(method: 'GET', path: '/shops');
    final items = (data['items'] as List<dynamic>);
    return items
        .map((e) => Shop.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<Shop> createShop({
    required String name,
    String? currency,
    String? timezone,
    String? openingDate,
  }) async {
    final data = await _send(
      method: 'POST',
      path: '/shops',
      body: {
        'name': name,
        if (currency != null) 'currency': currency,
        if (timezone != null) 'timezone': timezone,
        if (openingDate != null) 'openingDate': openingDate,
      },
    );
    return Shop.fromJson(data);
  }

  Future<Shop> getShop(String shopId) async {
    final data = await _send(method: 'GET', path: '/shops/$shopId');
    return Shop.fromJson(data);
  }

  Future<Shop> updateShop(
    String shopId, {
    String? name,
    String? currency,
    String? timezone,
    String? openingDate,
  }) async {
    final data = await _send(
      method: 'PATCH',
      path: '/shops/$shopId',
      body: {
        if (name != null) 'name': name,
        if (currency != null) 'currency': currency,
        if (timezone != null) 'timezone': timezone,
        if (openingDate != null) 'openingDate': openingDate,
      },
    );
    return Shop.fromJson(data);
  }

  // ---------------------------------------------------------------------------
  // العملاء
  // ---------------------------------------------------------------------------

  Future<List<Customer>> listCustomers(String shopId, {String? search}) async {
    final query = (search != null && search.trim().isNotEmpty)
        ? '?search=${Uri.encodeQueryComponent(search.trim())}'
        : '';
    final data =
        await _send(method: 'GET', path: '/shops/$shopId/customers$query');
    final items = data['items'] as List<dynamic>;
    return items
        .map((e) => Customer.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<Customer> createCustomer(
    String shopId, {
    required String displayName,
    String? phone,
    String? notes,
  }) async {
    final data = await _send(
      method: 'POST',
      path: '/shops/$shopId/customers',
      body: {
        'displayName': displayName,
        if (phone != null) 'phone': phone,
        if (notes != null) 'notes': notes,
      },
    );
    return Customer.fromJson(data);
  }

  Future<Customer> getCustomer(String shopId, String customerId) async {
    final data =
        await _send(method: 'GET', path: '/shops/$shopId/customers/$customerId');
    return Customer.fromJson(data);
  }

  Future<Customer> updateCustomer(
    String shopId,
    String customerId, {
    String? displayName,
    String? phone,
    String? notes,
  }) async {
    final data = await _send(
      method: 'PATCH',
      path: '/shops/$shopId/customers/$customerId',
      body: {
        if (displayName != null) 'displayName': displayName,
        if (phone != null) 'phone': phone,
        if (notes != null) 'notes': notes,
      },
    );
    return Customer.fromJson(data);
  }

  Future<void> archiveCustomer(String shopId, String customerId) async {
    await _send(
      method: 'DELETE',
      path: '/shops/$shopId/customers/$customerId',
    );
  }

  Future<Invitation> createInvitation(String shopId, String customerId) async {
    final data = await _send(
      method: 'POST',
      path: '/shops/$shopId/customers/$customerId/invitations',
    );
    return Invitation.fromJson(data);
  }

  // ---------------------------------------------------------------------------
  // المراسلة مع العميل
  // ---------------------------------------------------------------------------

  Future<List<ConversationMessage>> listCustomerMessages(
    String shopId,
    String customerId,
  ) async {
    final data = await _send(
      method: 'GET',
      path: '/shops/$shopId/customers/$customerId/messages',
    );
    final items = data['items'] as List<dynamic>? ?? const [];
    return items
        .map((item) => ConversationMessage.fromJson(
              item as Map<String, dynamic>,
            ))
        .toList(growable: false);
  }

  Future<ConversationMessage> sendCustomerMessage(
    String shopId,
    String customerId,
    String body,
  ) async {
    final data = await _send(
      method: 'POST',
      path: '/shops/$shopId/customers/$customerId/messages',
      body: {'body': body},
    );
    return ConversationMessage.fromJson(data);
  }

  // ---------------------------------------------------------------------------
  // المشتريات الآجلة
  // ---------------------------------------------------------------------------

  Future<List<Purchase>> listPurchases(String shopId, {String? customerId}) async {
    final query = (customerId != null && customerId.isNotEmpty)
        ? '?customerId=$customerId'
        : '';
    final data =
        await _send(method: 'GET', path: '/shops/$shopId/purchases$query');
    final items = data['items'] as List<dynamic>;
    return items
        .map((e) => Purchase.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<Purchase> createPurchase(
    String shopId, {
    required String customerId,
    required String itemsText,
    required int totalAmount,
    int paidAmount = 0,
    String? notes,
    String? id,
    String? idempotencyKey,
  }) async {
    final data = await _send(
      method: 'POST',
      path: '/shops/$shopId/purchases',
      headers: idempotencyKey == null ? null : {'idempotency-key': idempotencyKey},
      body: {
        if (id != null) 'id': id,
        'customerId': customerId,
        'itemsText': itemsText,
        'totalAmount': totalAmount,
        'paidAmount': paidAmount,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      },
    );
    return Purchase.fromJson(data);
  }

  Future<Purchase> getPurchase(String shopId, String purchaseId) async {
    final data =
        await _send(method: 'GET', path: '/shops/$shopId/purchases/$purchaseId');
    return Purchase.fromJson(data);
  }

  // ---------------------------------------------------------------------------
  // المدفوعات
  // ---------------------------------------------------------------------------

  Future<List<Payment>> listPayments(String shopId, {String? customerId}) async {
    final query = (customerId != null && customerId.isNotEmpty)
        ? '?customerId=$customerId'
        : '';
    final data =
        await _send(method: 'GET', path: '/shops/$shopId/payments$query');
    final items = data['items'] as List<dynamic>;
    return items
        .map((e) => Payment.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<Payment> createPayment(
    String shopId, {
    required String customerId,
    required int amount,
    String? purchaseId,
    String? notes,
    String? id,
    String? idempotencyKey,
  }) async {
    final data = await _send(
      method: 'POST',
      path: '/shops/$shopId/payments',
      headers: idempotencyKey == null ? null : {'idempotency-key': idempotencyKey},
      body: {
        if (id != null) 'id': id,
        'customerId': customerId,
        if (purchaseId != null) 'purchaseId': purchaseId,
        'amount': amount,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      },
    );
    return Payment.fromJson(data);
  }

  Future<Payment> getPayment(String shopId, String paymentId) async {
    final data =
        await _send(method: 'GET', path: '/shops/$shopId/payments/$paymentId');
    return Payment.fromJson(data);
  }

  // ---------------------------------------------------------------------------
  // كشف الحساب
  // ---------------------------------------------------------------------------

  Future<CustomerStatement> getStatement(
    String shopId,
    String customerId, {
    String? type,
    String? from,
    String? to,
  }) async {
    final params = <String>[
      if (type != null && type != 'all') 'type=$type',
      if (from != null && from.isNotEmpty)
        'from=${Uri.encodeQueryComponent(from)}',
      if (to != null && to.isNotEmpty) 'to=${Uri.encodeQueryComponent(to)}',
    ];
    final query = params.isEmpty ? '' : '?${params.join('&')}';
    final data = await _send(
      method: 'GET',
      path: '/shops/$shopId/customers/$customerId/statement$query',
    );
    return CustomerStatement.fromJson(data);
  }

  // ---------------------------------------------------------------------------
  // المرتجعات
  // ---------------------------------------------------------------------------

  Future<List<PurchaseReturn>> listReturns(
    String shopId, {
    String? customerId,
  }) async {
    final query = (customerId != null && customerId.isNotEmpty)
        ? '?customerId=$customerId'
        : '';
    final data = await _send(method: 'GET', path: '/shops/$shopId/returns$query');
    final items = data['items'] as List<dynamic>;
    return items
        .map((e) => PurchaseReturn.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<PurchaseReturn> createReturn(
    String shopId, {
    required String purchaseId,
    required int amount,
    String? reason,
    String? id,
    String? occurredAt,
    String? idempotencyKey,
  }) async {
    final data = await _send(
      method: 'POST',
      path: '/shops/$shopId/returns',
      headers:
          idempotencyKey == null ? null : {'idempotency-key': idempotencyKey},
      body: {
        if (id != null) 'id': id,
        'purchaseId': purchaseId,
        'amount': amount,
        if (reason != null && reason.isNotEmpty) 'reason': reason,
        if (occurredAt != null) 'occurredAt': occurredAt,
      },
    );
    return PurchaseReturn.fromJson(data);
  }

  // ---------------------------------------------------------------------------
  // التصحيحات المالية والإلغاءات
  // ---------------------------------------------------------------------------

  Future<List<FinancialAdjustment>> listAdjustments(
    String shopId, {
    String? customerId,
  }) async {
    final query = (customerId != null && customerId.isNotEmpty)
        ? '?customerId=$customerId'
        : '';
    final data =
        await _send(method: 'GET', path: '/shops/$shopId/adjustments$query');
    final items = data['items'] as List<dynamic>;
    return items
        .map((e) => FinancialAdjustment.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<FinancialAdjustment> createAdjustment(
    String shopId, {
    required String customerId,
    required int amount,
    required String reason,
    String? relatedPurchaseId,
    String? id,
    String? occurredAt,
    String? idempotencyKey,
  }) async {
    final data = await _send(
      method: 'POST',
      path: '/shops/$shopId/adjustments',
      headers:
          idempotencyKey == null ? null : {'idempotency-key': idempotencyKey},
      body: {
        if (id != null) 'id': id,
        'customerId': customerId,
        if (relatedPurchaseId != null) 'relatedPurchaseId': relatedPurchaseId,
        'amount': amount,
        'reason': reason,
        if (occurredAt != null) 'occurredAt': occurredAt,
      },
    );
    return FinancialAdjustment.fromJson(data);
  }

  Future<FinancialAdjustment> cancelPurchase(
    String shopId,
    String purchaseId, {
    required String reason,
    String? id,
    String? occurredAt,
    String? idempotencyKey,
    required int version,
  }) async {
    final data = await _send(
      method: 'POST',
      path: '/shops/$shopId/purchases/$purchaseId/cancel',
      headers:
          idempotencyKey == null ? null : {'idempotency-key': idempotencyKey},
      body: {
        if (id != null) 'id': id,
        'reason': reason,
        if (occurredAt != null) 'occurredAt': occurredAt,
        'version': version,
      },
    );
    return FinancialAdjustment.fromJson(data);
  }

  // ---------------------------------------------------------------------------
  // سجل التدقيق
  // ---------------------------------------------------------------------------

  Future<List<AuditEntry>> listAuditLogs(
    String shopId, {
    String? entityType,
    String? entityId,
    String? action,
    int? limit,
  }) async {
    final params = <String>[
      if (entityType != null && entityType.isNotEmpty) 'entityType=$entityType',
      if (entityId != null && entityId.isNotEmpty) 'entityId=$entityId',
      if (action != null && action.isNotEmpty) 'action=$action',
      if (limit != null) 'limit=$limit',
    ];
    final query = params.isEmpty ? '' : '?${params.join('&')}';
    final data =
        await _send(method: 'GET', path: '/shops/$shopId/audit-logs$query');
    final items = data['items'] as List<dynamic>;
    return items
        .map((e) => AuditEntry.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  // ---------------------------------------------------------------------------
  // النواة
  // ---------------------------------------------------------------------------

  /// يرسل طلبًا ويعيد حقل `data` مع معالجة موحّدة للأخطاء والتجديد.
  Future<Map<String, dynamic>> _send({
    required String method,
    required String path,
    Map<String, dynamic>? body,
    Map<String, String>? headers,
    bool allowRetry = true,
  }) async {
    final access = await _tokens.readAccessToken();
    http.Response response;
    try {
      response =
          await _request(method, path, body, access, headers).timeout(_timeout);
    } on ApiException {
      rethrow;
    } catch (e) {
      debugPrint('[WIZANO-API] network error on $path: $e');
      throw const ApiException(
        message: 'تعذر الوصول إلى الخادم. تحقق من اتصال الشبكة.',
        code: 'NETWORK_ERROR',
      );
    }

    if (response.statusCode == 401 && allowRetry) {
      final refreshed = await _tryRefresh();
      if (refreshed) {
        return _send(
          method: method,
          path: path,
          body: body,
          headers: headers,
          allowRetry: false,
        );
      }
    }

    return _decode(response);
  }

  Future<http.Response> _request(
    String method,
    String path,
    Map<String, dynamic>? body,
    String? access, [
    Map<String, String>? extraHeaders,
  ]) {
    final uri = _uri(path);
    final encoded = body == null ? null : jsonEncode(body);
    final headers = {
      ..._headers(access, withBody: encoded != null),
      ...?extraHeaders,
    };
    switch (method) {
      case 'GET':
        return _http.get(uri, headers: headers);
      case 'POST':
        return _http.post(uri, headers: headers, body: encoded);
      case 'PATCH':
        return _http.patch(uri, headers: headers, body: encoded);
      case 'PUT':
        return _http.put(uri, headers: headers, body: encoded);
      case 'DELETE':
        return _http.delete(uri, headers: headers, body: encoded);
      default:
        throw ApiException(message: 'طريقة غير مدعومة.', code: 'BAD_METHOD');
    }
  }

  Future<bool> _tryRefresh() async {
    final refresh = await _tokens.readRefreshToken();
    if (refresh == null) return false;
    try {
      final response = await _http
          .post(
            _uri('/auth/refresh'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({'refreshToken': refresh}),
          )
          .timeout(_timeout);
      if (response.statusCode != 200) return false;
      final data = _decode(response);
      final tokens = AuthTokens.fromJson(data['tokens'] as Map<String, dynamic>);
      await _tokens.saveTokens(
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// يفكّ استجابة الخادم الموحّدة `{ data }` أو `{ error }`.
  Map<String, dynamic> _decode(http.Response response) {
    // استجابة ناجحة بلا جسم (204 مثلاً) — لا شيء لفكّه.
    if ((response.statusCode >= 200 && response.statusCode < 300) &&
        response.bodyBytes.isEmpty) {
      return const {};
    }

    Map<String, dynamic> json;
    try {
      json = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException(
        message: 'رد غير مفهوم من الخادم (رمز ${response.statusCode}).',
        code: 'BAD_RESPONSE',
        statusCode: response.statusCode,
      );
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return (json['data'] as Map<String, dynamic>?) ?? const {};
    }

    final error = json['error'] as Map<String, dynamic>?;
    throw ApiException(
      message: (error?['message_ar'] as String?) ??
          'حدث خطأ غير متوقع (رمز ${response.statusCode}).',
      code: (error?['code'] as String?) ?? 'UNKNOWN',
      statusCode: response.statusCode,
    );
  }
}

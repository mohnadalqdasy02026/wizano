import 'sync_status.dart';

/// نموذج المستخدم كما يعيده الخادم (`GET /api/v1/me`، واستجابات المصادقة).
class User {
  const User({
    required this.id,
    required this.displayName,
    required this.email,
    this.phone,
  });

  final String id;
  final String displayName;
  final String email;
  final String? phone;

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'] as String,
        displayName: json['displayName'] as String,
        email: (json['email'] as String?) ?? '',
        phone: json['phone'] as String?,
      );

  /// نسخة قابلة للتخزين محليًا (لعرضه دون اتصال).
  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        'email': email,
        'phone': phone,
      };
}

/// رمزا الوصول والتجديد.
class AuthTokens {
  const AuthTokens({required this.accessToken, required this.refreshToken});

  final String accessToken;
  final String refreshToken;

  factory AuthTokens.fromJson(Map<String, dynamic> json) => AuthTokens(
        accessToken: json['accessToken'] as String,
        refreshToken: json['refreshToken'] as String,
      );
}

/// نتيجة تسجيل/دخول: المستخدم + الرموز.
class AuthSession {
  const AuthSession({required this.user, required this.tokens});

  final User user;
  final AuthTokens tokens;

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
        user: User.fromJson(json['user'] as Map<String, dynamic>),
        tokens: AuthTokens.fromJson(json['tokens'] as Map<String, dynamic>),
      );
}

/// محل كما يعيده الخادم.
class Shop {
  const Shop({
    required this.id,
    required this.name,
    required this.currency,
    required this.timezone,
    this.openingDate,
    required this.status,
    this.role,
  });

  final String id;
  final String name;
  final String currency;
  final String timezone;
  final String? openingDate;
  final String status;

  /// دور المستخدم الحالي في هذا المحل (owner/member) — يُعاد في القائمة.
  final String? role;

  bool get isOwner => role == 'owner';

  factory Shop.fromJson(Map<String, dynamic> json) => Shop(
        id: json['id'] as String,
        name: json['name'] as String,
        currency: json['currency'] as String,
        timezone: json['timezone'] as String,
        openingDate: json['openingDate'] as String?,
        status: json['status'] as String,
        role: json['role'] as String?,
      );
}

/// عميل كما يعيده الخادم.
class Customer {
  const Customer({
    required this.id,
    required this.displayName,
    this.phone,
    this.notes,
    this.archivedAt,
  });

  final String id;
  final String displayName;
  final String? phone;
  final String? notes;
  final String? archivedAt;

  factory Customer.fromJson(Map<String, dynamic> json) => Customer(
        id: json['id'] as String,
        displayName: json['displayName'] as String,
        phone: json['phone'] as String?,
        notes: json['notes'] as String?,
        archivedAt: json['archivedAt'] as String?,
      );
}

/// رمز دعوة لربط العميل بالمحل.
class Invitation {
  const Invitation({
    required this.id,
    required this.code,
    required this.status,
    required this.expiresAt,
  });

  final String id;
  final String code;
  final String status;
  final String expiresAt;

  factory Invitation.fromJson(Map<String, dynamic> json) => Invitation(
        id: json['id'] as String,
        code: json['code'] as String,
        status: json['status'] as String,
        expiresAt: json['expiresAt'] as String,
      );
}

/// عملية شراء آجلة كما يعيدها الخادم.
///
/// المبالغ أعداد صحيحة بالريال اليمني، وتصل كنصوص (bigint) فتُحوَّل إلى int.
class Purchase {
  const Purchase({
    required this.id,
    required this.shopId,
    required this.customerId,
    required this.shopSeq,
    required this.occurredAt,
    required this.itemsText,
    required this.totalAmount,
    required this.paidAmount,
    required this.remainingAmount,
    this.notes,
    required this.status,
    this.statusReason,
    this.balanceAfter,
    this.syncStatus = SyncStatus.synced,
    required this.version,
  });

  final String id;
  final String shopId;
  final String customerId;

  /// رقم العملية الفريد ضمن المحل.
  final String shopSeq;
  final String occurredAt;
  final String itemsText;
  final int totalAmount;
  final int paidAmount;
  final int remainingAmount;
  final String? notes;
  final String status;
  final String? statusReason;

/// حالة المزامنة: عملية محلية غير متزامنة لا تُعرض كمعتمدة.
  final SyncStatus syncStatus;

/// رصيد العميل بعد هذه العملية (مشتق) — قد يكون null قبل الاحتساب.
  final int? balanceAfter;

  /// إصدار العملية (قفل تفاؤلي).
  final int version;

  factory Purchase.fromJson(Map<String, dynamic> json) => Purchase(
        id: json['id'] as String,
        shopId: json['shopId'] as String,
        customerId: json['customerId'] as String,
        shopSeq: json['shopSeq'].toString(),
        occurredAt: json['occurredAt'] as String,
        itemsText: json['itemsText'] as String,
        totalAmount: _asInt(json['totalAmount']),
        paidAmount: _asInt(json['paidAmount']),
        remainingAmount: _asInt(json['remainingAmount']),
        notes: json['notes'] as String?,
        status: (json['status'] as String?) ?? 'active',
        statusReason: json['statusReason'] as String?,
        balanceAfter:
            json['balanceAfter'] == null ? null : _asInt(json['balanceAfter']),
        version: (json['version'] != null) ? _asInt(json['version']) : 1,
      );
}

/// سطر واحد في كشف الحساب (عملية شراء أو دفعة) مع أثره على الرصيد.
class StatementEntry {
  const StatementEntry({
    required this.id,
    required this.type,
    this.shopSeq,
    required this.occurredAt,
    required this.description,
    required this.effect,
    required this.balanceAfter,
    required this.status,
    this.purchaseId,
    this.adjustmentKind,
  });

  final String id;

  /// نوع العملية: `purchase` أو `payment` أو `return` أو `adjustment`.
  final String type;
  final String? shopSeq;
  final String occurredAt;
  final String description;

  /// الأثر على الرصيد: موجب للمشتريات/التصحيح الموجب، سالب للمدفوعات/المرتجعات/التصحيح السالب.
  final int effect;

  /// الرصيد الجاري بعد هذه العملية.
  final int balanceAfter;
  final String status;

  /// العملية المرتبطة (للدفعات والمرتجعات والإلغاءات).
  final String? purchaseId;

  /// نوع التصحيح: `correction` أو `cancellation` (لأسطر adjustment فقط).
  final String? adjustmentKind;

  bool get isPurchase => type == 'purchase';
  bool get isReturn => type == 'return';
  bool get isAdjustment => type == 'adjustment';

  factory StatementEntry.fromJson(Map<String, dynamic> json) => StatementEntry(
        id: json['id'] as String,
        type: json['type'] as String,
        shopSeq: json['shopSeq']?.toString(),
        occurredAt: json['occurredAt'] as String,
        description: (json['description'] as String?) ?? '',
        effect: _asInt(json['effect']),
        balanceAfter: _asInt(json['balanceAfter']),
        status: (json['status'] as String?) ?? 'active',
        purchaseId: json['purchaseId'] as String?,
        adjustmentKind: json['adjustmentKind'] as String?,
      );
}

/// كشف حساب عميل: الإجماليات + العمليات زمنيًا مع الرصيد الجاري.
class CustomerStatement {
  const CustomerStatement({
    required this.customerId,
    required this.totalPurchases,
    required this.totalPayments,
    this.totalReturns = 0,
    this.totalAdjustments = 0,
    required this.balance,
    required this.entries,
  });

  final String customerId;
  final int totalPurchases;
  final int totalPayments;
  final int totalReturns;
  final int totalAdjustments;

  /// الرصيد الحالي = Σ مشتريات − Σ مدفوعات − Σ مرتجعات ± Σ تصحيحات.
  final int balance;
  final List<StatementEntry> entries;

  factory CustomerStatement.fromJson(Map<String, dynamic> json) =>
      CustomerStatement(
        customerId: json['customerId'] as String,
        totalPurchases: _asInt(json['totalPurchases']),
        totalPayments: _asInt(json['totalPayments']),
        totalReturns: _asInt(json['totalReturns'] ?? 0),
        totalAdjustments: _asInt(json['totalAdjustments'] ?? 0),
        balance: _asInt(json['balance']),
        entries: (json['entries'] as List<dynamic>)
            .map((e) => StatementEntry.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
      );
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.parse(value.toString());
}

/// دفعة على حساب عميل كما يعيدها الخادم (عامة أو مرتبطة بعملية).
///
/// المبلغ عدد صحيح بالريال اليمني، ويصل كنص (bigint) فيُحوَّل إلى int.
class Payment {
  const Payment({
    required this.id,
    required this.shopId,
    required this.customerId,
    this.purchaseId,
    required this.amount,
    required this.paidAt,
    this.shopSeq,
    this.notes,
    this.balanceAfter,
    this.syncStatus = SyncStatus.synced,
  });

  final String id;
  final String shopId;
  final String customerId;

  /// العملية المرتبطة (إن وُجدت) — وإلا فهي دفعة عامة على الحساب.
  final String? purchaseId;
  final int amount;
  final String paidAt;

  /// رقم الدفعة الفريد ضمن المحل.
  final String? shopSeq;
  final String? notes;

  /// رصيد العميل بعد هذه الدفعة (مشتق).
  final int? balanceAfter;

  /// حالة المزامنة: دفعة محلية غير متزامنة لا تُعرض كمعتمدة.
  final SyncStatus syncStatus;


  factory Payment.fromJson(Map<String, dynamic> json) => Payment(
        id: json['id'] as String,
        shopId: json['shopId'] as String,
        customerId: json['customerId'] as String,
        purchaseId: json['purchaseId'] as String?,
        amount: _asInt(json['amount']),
        paidAt: json['paidAt'] as String,
        shopSeq: json['shopSeq']?.toString(),
        notes: json['notes'] as String?,
        balanceAfter:
            json['balanceAfter'] == null ? null : _asInt(json['balanceAfter']),
      );
}

/// مرتجع مرتبط بعملية شراء — قيد يخصم قيمته من رصيد العميل.
class PurchaseReturn {
  const PurchaseReturn({
    required this.id,
    required this.shopId,
    required this.customerId,
    required this.purchaseId,
    required this.amount,
    this.reason,
    required this.occurredAt,
    this.balanceAfter,
  });

  final String id;
  final String shopId;
  final String customerId;

  /// العملية الأصلية التي يرتبط بها المرتجع.
  final String purchaseId;
  final int amount;
  final String? reason;
  final String occurredAt;

  /// رصيد العميل بعد هذا المرتجع (مشتق).
  final int? balanceAfter;

  factory PurchaseReturn.fromJson(Map<String, dynamic> json) => PurchaseReturn(
        id: json['id'] as String,
        shopId: json['shopId'] as String,
        customerId: json['customerId'] as String,
        purchaseId: json['purchaseId'] as String,
        amount: _asInt(json['amount']),
        reason: json['reason'] as String?,
        occurredAt: json['occurredAt'] as String,
        balanceAfter:
            json['balanceAfter'] == null ? null : _asInt(json['balanceAfter']),
      );
}

/// تصحيح مالي أو إلغاء عملية — مبلغ موقّع (موجب يزيد، سالب يخصم) مع سبب إلزامي.
class FinancialAdjustment {
  const FinancialAdjustment({
    required this.id,
    required this.shopId,
    required this.customerId,
    this.relatedPurchaseId,
    required this.kind,
    required this.amount,
    required this.reason,
    required this.occurredAt,
    this.balanceAfter,
  });

  final String id;
  final String shopId;
  final String customerId;

  /// العملية المرتبطة (للإلغاء إلزامية، وللتصحيح اختيارية).
  final String? relatedPurchaseId;

  /// `correction` (تصحيح) أو `cancellation` (إلغاء عملية).
  final String kind;
  final int amount;
  final String reason;
  final String occurredAt;

  /// رصيد العميل بعد هذا الإجراء (مشتق).
  final int? balanceAfter;

  bool get isCancellation => kind == 'cancellation';

  factory FinancialAdjustment.fromJson(Map<String, dynamic> json) =>
      FinancialAdjustment(
        id: json['id'] as String,
        shopId: json['shopId'] as String,
        customerId: json['customerId'] as String,
        relatedPurchaseId: json['relatedPurchaseId'] as String?,
        kind: json['kind'] as String,
        amount: _asInt(json['amount']),
        reason: json['reason'] as String,
        occurredAt: json['occurredAt'] as String,
        balanceAfter:
            json['balanceAfter'] == null ? null : _asInt(json['balanceAfter']),
      );
}

/// سطر سجل تدقيق — إجراء مالي موثَّق (المستخدم/الوقت/العملية/قبل-بعد).
class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.shopId,
    this.actorUserId,
    required this.action,
    required this.entityType,
    required this.entityId,
    this.before,
    this.after,
    required this.createdAt,
  });

  final String id;
  final String shopId;
  final String? actorUserId;
  final String action;
  final String entityType;
  final String entityId;
  final Map<String, dynamic>? before;
  final Map<String, dynamic>? after;
  final String createdAt;

  factory AuditEntry.fromJson(Map<String, dynamic> json) => AuditEntry(
        id: json['id'] as String,
        shopId: json['shopId'] as String,
        actorUserId: json['actorUserId'] as String?,
        action: json['action'] as String,
        entityType: json['entityType'] as String,
        entityId: json['entityId'] as String,
        before: json['before'] == null
            ? null
            : (json['before'] as Map<String, dynamic>),
        after:
            json['after'] == null ? null : (json['after'] as Map<String, dynamic>),
        createdAt: json['createdAt'] as String,
      );
}

/// رسالة خاصة (نصية أو صوتية) بين المحل والعميل.
class ConversationMessage {
  const ConversationMessage({
    required this.id,
    this.body,
    required this.senderType,
    required this.createdAt,
    this.readAt,
    this.audioBase64,
    this.audioMimeType,
    this.audioDurationMs,
    this.pending = false,
  });

  final String id;
  final String? body;
  final String senderType;
  final String createdAt;
  final String? readAt;
  final String? audioBase64;
  final String? audioMimeType;
  final int? audioDurationMs;
  final bool pending;

  bool get isFromShop => senderType == 'shop';

  factory ConversationMessage.fromJson(Map<String, dynamic> json) =>
      ConversationMessage(
        id: json['id'] as String,
        body: json['body'] as String?,
        senderType: json['senderType'] as String,
        createdAt: json['createdAt'] as String,
        readAt: json['readAt'] as String?,
        audioBase64: json['audioBase64'] as String?,
        audioMimeType: json['audioMimeType'] as String?,
        audioDurationMs: json['audioDurationMs'] as int?,
        pending: json['pending'] as bool? ?? false,
      );
}

/// ملخص محادثة لعرض قائمة الرسائل مع آخر رسالة والعدد غير المقروء.
class ConversationSummary {
  const ConversationSummary({
    required this.customerId,
    required this.customerName,
    required this.lastBody,
    required this.lastIsAudio,
    required this.lastCreatedAt,
    required this.unreadCount,
  });

  final String customerId;
  final String customerName;
  final String? lastBody;
  final bool lastIsAudio;
  final String lastCreatedAt;
  final int unreadCount;

  factory ConversationSummary.fromJson(Map<String, dynamic> json) =>
      ConversationSummary(
        customerId: json['customerId'] as String,
        customerName: json['customerName'] as String,
        lastBody: json['lastBody'] as String?,
        lastIsAudio: json['lastIsAudio'] as bool? ?? false,
        lastCreatedAt: json['lastCreatedAt'] as String,
        unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
      );
}



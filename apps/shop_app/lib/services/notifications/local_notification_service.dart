import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// وجهة فُتحت من إشعار (محادثة عميل محددة).
class NotificationTarget {
  const NotificationTarget({required this.conversationId, this.senderName = ''});

  final String conversationId;
  final String senderName;

  static NotificationTarget? fromArguments(Object? arguments) {
    if (arguments is! Map) return null;
    final conversationId = arguments['conversationId']?.toString() ?? '';
    if (conversationId.isEmpty) return null;
    return NotificationTarget(
      conversationId: conversationId,
      senderName: arguments['senderName']?.toString() ?? '',
    );
  }
}

/// إشعارات هاتف محلية للرسائل الجديدة أثناء تشغيل التطبيق.
/// الإشعار يعرض اسم العميل ونص رسالته (نمط المحادثات كما في واتساب)،
/// والضغط عليه يفتح المحادثة مباشرة. لا يحتوي أي تفاصيل مالية.
class LocalNotificationService {
  static const _channel = MethodChannel('com.wizano.shop_app/notifications');

  final StreamController<NotificationTarget> _taps =
      StreamController<NotificationTarget>.broadcast();

  bool _ready = false;

  /// إشعار ضغط عليه المستخدم والتطبيق يعمل.
  Stream<NotificationTarget> get onTap => _taps.stream;

  Future<void> initialize() async {
    if (!Platform.isAndroid) return;
    _channel.setMethodCallHandler(_handleNativeCall);
    try {
      await _channel.invokeMethod<void>('requestPermission');
      _ready = true;
    } on PlatformException {
      // عدم دعم الإشعار لا يجب أن يعطل واجهة المحل أو الرسائل.
      _ready = false;
    } on MissingPluginException {
      _ready = false;
    }
  }

  Future<Object?> _handleNativeCall(MethodCall call) async {
    if (call.method == 'onNotificationTap') {
      final target = NotificationTarget.fromArguments(call.arguments);
      if (target != null && !_taps.isClosed) _taps.add(target);
    }
    return null;
  }

  /// يُستدعى عند إقلاع التطبيق أو عودته للواجهة: هل فُتح من إشعار؟
  Future<NotificationTarget?> consumeTarget() async {
    if (!Platform.isAndroid) return null;
    try {
      final arguments = await _channel.invokeMethod<Object?>('consumeTarget');
      return NotificationTarget.fromArguments(arguments);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<void> showNewMessage({
    required String conversationId,
    required String senderName,
    required String? body,
    required int count,
    String? shopId,
    DateTime? at,
  }) async {
    if (!_ready || count < 1) return;
    final text = (body ?? '').trim();
    try {
      await _channel.invokeMethod<void>('showMessage', {
        'conversationId': conversationId,
        'senderName': senderName.isEmpty ? 'عميل' : senderName,
        'body': text.isEmpty ? 'أرسل لك رسالة جديدة' : text,
        'count': count,
        'shopId': shopId,
        'timestampMs': (at ?? DateTime.now()).millisecondsSinceEpoch,
      });
    } on PlatformException {
      // يبقى عداد الرسائل داخل التطبيق مرئيًا حتى إن رفض المستخدم الإذن.
    }
  }

  /// يحفظ جلسة الرد المباشر لدى الجهة الأصلية (رمز الوصول ورابط الخادم)
  /// ليتمكن «رد» داخل الإشعار من الإرسال دون فتح التطبيق.
  Future<void> setReplySession({
    required String apiBase,
    required String accessToken,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('setReplySession', {
        'apiBase': apiBase,
        'accessToken': accessToken,
      });
    } on PlatformException {
      // بدون جلسة يظهر زر الرد لكن الإرسال يتطلب فتح التطبيق لاحقًا.
    } on MissingPluginException {
      // ignore
    }
  }

  Future<void> clearReplySession() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('clearReplySession');
    } on PlatformException {
      // ignore
    } on MissingPluginException {
      // ignore
    }
  }

  void dispose() {
    _taps.close();
    _channel.setMethodCallHandler(null);
  }
}

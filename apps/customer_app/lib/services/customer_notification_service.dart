import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// وجهة فُتحت من إشعار (محادثة محل محددة).
class CustomerNotificationTarget {
  const CustomerNotificationTarget({required this.shopId, this.shopName = ''});

  final String shopId;
  final String shopName;

  static CustomerNotificationTarget? fromArguments(Object? arguments) {
    if (arguments is! Map) return null;
    final shopId = arguments['shopId']?.toString() ?? '';
    if (shopId.isEmpty) return null;
    return CustomerNotificationTarget(
      shopId: shopId,
      shopName: arguments['shopName']?.toString() ?? '',
    );
  }
}

/// إشعار محلي عند وصول رسالة جديدة من محل مرتبط أثناء تشغيل التطبيق.
/// يعرض نص الرسالة (نمط المحادثات كما في واتساب)، والضغط يفتح المحادثة.
class CustomerNotificationService {
  static const MethodChannel _channel =
      MethodChannel('com.wizano.customer_app/notifications');

  final StreamController<CustomerNotificationTarget> _taps =
      StreamController<CustomerNotificationTarget>.broadcast();

  bool _ready = false;

  Stream<CustomerNotificationTarget> get onTap => _taps.stream;

  Future<void> initialize() async {
    if (!Platform.isAndroid) return;
    _channel.setMethodCallHandler(_handleNativeCall);
    try {
      await _channel.invokeMethod<void>('requestPermission');
      _ready = true;
    } on PlatformException {
      // يستمر التطبيق حتى إن لم يدعم الهاتف الإشعارات.
      _ready = false;
    } on MissingPluginException {
      _ready = false;
    }
  }

  Future<Object?> _handleNativeCall(MethodCall call) async {
    if (call.method == 'onNotificationTap') {
      final target = CustomerNotificationTarget.fromArguments(call.arguments);
      if (target != null && !_taps.isClosed) _taps.add(target);
    }
    return null;
  }

  /// يُستدعى عند الإقلاع أو العودة للواجهة: هل فُتح التطبيق من إشعار؟
  Future<CustomerNotificationTarget?> consumeTarget() async {
    if (!Platform.isAndroid) return null;
    try {
      final arguments = await _channel.invokeMethod<Object?>('consumeTarget');
      return CustomerNotificationTarget.fromArguments(arguments);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<void> showNewMessage({
    required String shopId,
    required String shopName,
    required String? body,
    required int count,
    DateTime? at,
  }) async {
    if (!_ready || count < 1) return;
    final text = (body ?? '').trim();
    try {
      await _channel.invokeMethod<void>('showMessage', {
        'shopId': shopId,
        'shopName': shopName.isEmpty ? 'المحل' : shopName,
        'body': text.isEmpty ? 'أرسل لك رسالة جديدة' : text,
        'count': count,
        'timestampMs': (at ?? DateTime.now()).millisecondsSinceEpoch,
      });
    } on PlatformException {
      // عداد الرسائل داخل التطبيق يبقى ظاهرًا.
    }
  }

  /// يحفظ جلسة الرد المباشر (رمز الوصول ورابط الخادم) لدى الجهة الأصلية
  /// ليرسل «رد» من داخل الإشعار دون فتح التطبيق.
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
      // ignore
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
}

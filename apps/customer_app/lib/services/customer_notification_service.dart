import 'dart:io';

import 'package:flutter/services.dart';

/// إشعار محلي عند وصول رسالة جديدة من محل مرتبط أثناء تشغيل التطبيق.
class CustomerNotificationService {
  static const _channel = MethodChannel('com.wizano.customer_app/notifications');
  bool _ready = false;

  Future<void> initialize() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('requestPermission');
      _ready = true;
    } on PlatformException {
      // يستمر التطبيق حتى إن لم يدعم الهاتف الإشعارات.
    }
  }

  Future<void> showNewMessage({
    required String shopId,
    required String shopName,
    required int count,
  }) async {
    if (!_ready || count < 1) return;
    try {
      await _channel.invokeMethod<void>('showMessage', {
        'id': shopId.hashCode,
        'shopName': shopName,
        'count': count,
      });
    } on PlatformException {
      // عداد الرسائل داخل التطبيق يبقى ظاهرًا.
    }
  }
}

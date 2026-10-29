import 'dart:io';

import 'package:flutter/services.dart';

/// إشعارات هاتف محلية للرسائل الجديدة أثناء تشغيل التطبيق.
/// الإشعار لا يحتوي تفاصيل مالية، ويحافظ على خصوصية بيانات العميل.
class LocalNotificationService {
  static const _channel = MethodChannel('com.wizano.shop_app/notifications');
  bool _ready = false;

  Future<void> initialize() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('requestPermission');
      _ready = true;
    } on PlatformException {
      // عدم دعم الإشعار لا يجب أن يعطل واجهة المحل أو الرسائل.
    }
  }

  Future<void> showNewMessage({
    required String customerName,
    required int count,
  }) async {
    if (!_ready) return;
    try {
      await _channel.invokeMethod<void>('showMessage', {
        'id': customerName.hashCode,
        'customerName': customerName,
        'count': count,
      });
    } on PlatformException {
      // يبقى عداد الرسائل داخل التطبيق مرئيًا حتى إن رفض المستخدم الإذن.
    }
  }
}

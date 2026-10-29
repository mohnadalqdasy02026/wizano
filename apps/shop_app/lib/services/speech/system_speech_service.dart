import 'dart:async';

import 'package:flutter/services.dart';

/// واجهة Android الرسمية للتعرّف على الكلام.
///
/// عند وجود اتصال تستعمل خدمة التعرّف المثبّتة في الهاتف (مثل خدمة Google)،
/// وهي أدق بكثير من نموذج Moonshine المحلي في أسماء المنتجات العربية واللهجات.
/// لا تمر البيانات عبر خادم WIZANO. عند غيابها يرجع التطبيق للمحرك المحلي.
class SystemSpeechService {
  static const _methods = MethodChannel('com.wizano.shop_app/system_speech');
  static const _events = EventChannel('com.wizano.shop_app/system_speech_events');

  Stream<SystemSpeechEvent>? _stream;

  Stream<SystemSpeechEvent> get events => _stream ??= _events
      .receiveBroadcastStream()
      .map((dynamic raw) {
        final data = Map<Object?, Object?>.from(raw as Map);
        return SystemSpeechEvent(
          type: data['type'] as String? ?? 'error',
          text: data['text'] as String? ?? '',
          message: data['message'] as String? ?? '',
        );
      });

  Future<bool> isAvailable() async {
    try {
      return await _methods.invokeMethod<bool>('isAvailable') ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> start() => _methods.invokeMethod<void>('start', {
        // اليمنية أولًا؛ يختار Android أقرب نموذج متاح عند عدم توفرها.
        'locale': 'ar-YE',
      });

  Future<void> stop() => _methods.invokeMethod<void>('stop');

  Future<void> cancel() => _methods.invokeMethod<void>('cancel');
}

class SystemSpeechEvent {
  const SystemSpeechEvent({
    required this.type,
    required this.text,
    required this.message,
  });

  final String type;
  final String text;
  final String message;
}

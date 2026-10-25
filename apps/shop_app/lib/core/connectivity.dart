import 'package:flutter/foundation.dart';

/// مراقب حالة الاتصال بالخادم.
///
/// يعكس آخر نتيجة معروفة من الشبكة: إن فشل أي طلب بسبب الشبكة نُعلن انقطاعها،
/// وإن نجح طلب نعلن عودة الاتصال. يُستخدم لعرض تنبيه واضح أثناء العمل دون
/// اتصال (العمليات تُحفظ محليًا) بدل أن يكتشف المستخدم ذلك عند الحفظ فقط.
class ConnectivityMonitor extends ChangeNotifier {
  bool _offline = false;
  DateTime? _since;

  /// هل آخر طلب فشل بسبب انقطاع الشبكة؟
  bool get offline => _offline;

  /// متى بدأ انقطاع الاتصال (إن كان منقطعًا).
  DateTime? get offlineSince => _since;

  void reportOffline() {
    if (_offline) return;
    _offline = true;
    _since = DateTime.now();
    notifyListeners();
  }

  void reportOnline() {
    if (!_offline) return;
    _offline = false;
    _since = null;
    notifyListeners();
  }
}

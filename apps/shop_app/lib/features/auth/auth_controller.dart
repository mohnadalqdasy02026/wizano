import 'package:flutter/foundation.dart';

import '../../core/api_exception.dart';
import '../../data/repositories/auth_repository.dart';
import '../../domain/entities/models.dart';

/// الحالات الممكنة لجلسة المستخدم.
enum AuthStatus { unknown, authenticated, unauthenticated }

/// يدير حالة جلسة المستخدم: الفحص عند البدء، الدخول، التسجيل، والخروج.
class AuthController extends ChangeNotifier {
  AuthController({
    required AuthRepository repository,
    Future<void> Function()? onLogout,
  })  : _repository = repository,
        _onLogout = onLogout;

  final AuthRepository _repository;

  /// يُستدعى عند الخروج لمسح البيانات المحلية (الطابور ونسخ العرض).
  final Future<void> Function()? _onLogout;

  AuthStatus _status = AuthStatus.unknown;
  User? _user;
  bool _busy = false;

  AuthStatus get status => _status;
  User? get user => _user;
  bool get busy => _busy;
  bool get isAuthenticated => _status == AuthStatus.authenticated;

  /// فحص الجلسة عند إقلاع التطبيق (يستعيد المستخدم إن وُجد رمز صالح).
  ///
  /// **دون اتصال:** إن كانت هناك جلسة محفوظة على الجهاز، يبقى المستخدم
  /// مسجّلًا ويعمل التطبيق محليًا (docs/03: «لا يُسمح بالعمل دون اتصال قبل
  /// نجاح تسجيل الدخول الأولي وحفظ الجلسة»).
  Future<void> bootstrap() async {
    _busy = true;
    notifyListeners();
    try {
      final user = await _repository.currentUser();
      _user = user;
      _status =
          user == null ? AuthStatus.unauthenticated : AuthStatus.authenticated;
    } catch (_) {
      // فشل الشبكة عند الإقلاع: إن كانت هناك جلسة محفوظة فالعمل مستمر محليًا.
      final hasSession = await _repository.hasStoredSession();
      if (hasSession) {
        _user = await _repository.cachedUser();
        _status = AuthStatus.authenticated;
      } else {
        _status = AuthStatus.unauthenticated;
      }
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// تسجيل الدخول — يعيد null عند النجاح أو رسالة الخطأ.
  Future<String?> login({required String email, required String password}) {
    return _run(() async {
      final session = await _repository.login(email: email, password: password);
      _user = session.user;
      _status = AuthStatus.authenticated;
    });
  }

  /// إنشاء حساب — يعيد null عند النجاح أو رسالة الخطأ.
  Future<String?> register({
    required String displayName,
    required String email,
    required String password,
  }) {
    return _run(() async {
      final session = await _repository.register(
        displayName: displayName,
        email: email,
        password: password,
      );
      _user = session.user;
      _status = AuthStatus.authenticated;
    });
  }

  Future<void> logout() async {
    _busy = true;
    notifyListeners();
    try {
      await _repository.logout();
    } finally {
      // مسح البيانات المحلية: لا تنتقل عمليات معلّقة لحساب آخر.
      try {
        await _onLogout?.call();
      } catch (_) {
        // فشل المسح لا يمنع الخروج.
      }
      _user = null;
      _status = AuthStatus.unauthenticated;
      _busy = false;
      notifyListeners();
    }
  }

  /// يعطّل الحساب ويزيل بياناته الشخصية من الخادم، ثم يمسح الجهاز محليًا.
  Future<String?> deleteAccount(String password) async {
    _busy = true;
    notifyListeners();
    try {
      await _repository.deleteAccount(password);
      await _onLogout?.call();
      _user = null;
      _status = AuthStatus.unauthenticated;
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'تعذر حذف الحساب الآن.';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<String> activeShopId() async =>
      (await _repository.readActiveShopId()) ?? '';

  Future<void> setActiveShopId(String? shopId) =>
      _repository.setActiveShopId(shopId);

  /// يُنفّذ عملية ويعيد رسالة الخطأ العربية أو null عند النجاح.
  Future<String?> _run(Future<void> Function() action) async {
    _busy = true;
    notifyListeners();
    try {
      await action();
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'حدث خطأ غير متوقع.';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}

import 'dart:convert';

import '../../core/api_exception.dart';
import '../../core/token_store.dart';
import '../../data/remote/api_client.dart';
import '../../domain/entities/models.dart';

/// واجهة منطق المصادقة — تفصل الواجهة عن تفاصيل الشبكة والتخزين.
abstract class AuthRepository {
  Future<AuthSession> register({
    required String displayName,
    required String email,
    required String password,
  });
  Future<AuthSession> login({required String email, required String password});
  Future<User?> currentUser();

  /// هل توجد جلسة محفوظة على الجهاز (تعمل دون اتصال)؟
  Future<bool> hasStoredSession();

  /// المستخدم المحفوظ محليًا (للعمل دون اتصال).
  Future<User?> cachedUser();

  Future<void> logout();
  Future<void> deleteAccount(String password);
  Future<String?> readActiveShopId();
  Future<void> setActiveShopId(String? shopId);
}

class ApiAuthRepository implements AuthRepository {
  ApiAuthRepository({
    required ApiClient api,
    required TokenStore tokenStore,
  })  : _api = api,
        _tokens = tokenStore;

  final ApiClient _api;
  final TokenStore _tokens;

  @override
  Future<AuthSession> register({
    required String displayName,
    required String email,
    required String password,
  }) async {
    final session = await _api.register(
      displayName: displayName,
      email: email,
      password: password,
    );
    await _saveSession(session);
    return session;
  }

  @override
  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    final session = await _api.login(email: email, password: password);
    await _saveSession(session);
    return session;
  }

  /// يحفظ الرموز وملف المستخدم ليعمل التطبيق دون اتصال.
  Future<void> _saveSession(AuthSession session) async {
    await _tokens.saveTokens(
      accessToken: session.tokens.accessToken,
      refreshToken: session.tokens.refreshToken,
    );
    await _tokens.saveUserProfile(jsonEncode(session.user.toJson()));
  }

  @override
  Future<bool> hasStoredSession() async {
    final access = await _tokens.readAccessToken();
    if (access != null && access.isNotEmpty) return true;
    final refresh = await _tokens.readRefreshToken();
    return refresh != null && refresh.isNotEmpty;
  }

  @override
  Future<User?> cachedUser() async {
    final raw = await _tokens.readUserProfile();
    if (raw == null || raw.isEmpty) return null;
    try {
      return User.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<User?> currentUser() async {
    final access = await _tokens.readAccessToken();
    if (access == null) return null;
    try {
      return await _api.me();
    } on ApiException catch (e) {
      if (e.isUnauthorized) {
        // لا نمسح الجلسة لمجرد 401 عابر: قد يحدث ذلك حين ينتهي access
        // token بينما Render نائم ولا يستطيع طلب التجديد الوصول في وقته.
        // يبقى المستخدم داخل التطبيق بالنسخة المحلية، ويعيد ApiClient المحاولة
        // تلقائيًا عند عودة الخادم. الخروج الصريح فقط هو الذي يمسح الرموز.
        rethrow;
      }
      rethrow;
    }
  }

  @override
  Future<void> logout() async {
    await _api.logout();
    await _tokens.clear();
  }

  @override
  Future<void> deleteAccount(String password) async {
    await _api.deleteAccount(password);
    await _tokens.clear();
  }

  @override
  Future<String?> readActiveShopId() => _tokens.readActiveShopId();

  @override
  Future<void> setActiveShopId(String? shopId) =>
      _tokens.saveActiveShopId(shopId);
}

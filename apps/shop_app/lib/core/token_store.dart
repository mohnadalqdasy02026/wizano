/// واجهة تخزين رموز المصادقة (وصول + تجديد) وسياق المحل النشط.
///
/// التنفيذ الحالي في الذاكرة ([InMemoryTokenStore]) — كافٍ لوظائف المرحلة 6
/// والاختبارات، وقابل للاستبدال بتنفيذ آمن على القرص (flutter_secure_storage)
/// لاحقًا **دون** تغيير أي مستهلك (AuthRepository/الواجهات).
abstract class TokenStore {
  Future<String?> readAccessToken();
  Future<String?> readRefreshToken();
  Future<String?> readActiveShopId();

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  });

  Future<void> saveActiveShopId(String? shopId);

  /// يحفظ ملف المستخدم (JSON) لعرضه دون اتصال.
  Future<void> saveUserProfile(String json);

  /// يقرأ ملف المستخدم المحفوظ (null إن لم يُحفظ).
  Future<String?> readUserProfile();

  Future<void> clear();
}

/// تنفيذ في الذاكرة — لا يكتب على القرص. مؤقت وآمن للمرحلة 6.
class InMemoryTokenStore implements TokenStore {
  String? _access;
  String? _refresh;
  String? _activeShopId;
  String? _userProfile;

  @override
  Future<String?> readAccessToken() async => _access;

  @override
  Future<String?> readRefreshToken() async => _refresh;

  @override
  Future<String?> readActiveShopId() async => _activeShopId;

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    _access = accessToken;
    _refresh = refreshToken;
  }

  @override
  Future<void> saveActiveShopId(String? shopId) async {
    _activeShopId = shopId;
  }

  @override
  Future<void> saveUserProfile(String json) async {
    _userProfile = json;
  }

  @override
  Future<String?> readUserProfile() async => _userProfile;

  @override
  Future<void> clear() async {
    _access = null;
    _refresh = null;
    _activeShopId = null;
    _userProfile = null;
  }
}

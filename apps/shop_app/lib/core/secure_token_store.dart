import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'token_store.dart';

/// تنفيذ آمن لتخزين رموز المصادقة على القرص (Keystore / Keychain).
///
/// يعالج بنية الواجهة نفسها (`TokenStore`) فلا يتغيّر أي مستهلك
/// (docs/04 §: التخزين في التطبيق = flutter_secure_storage).
class SecureTokenStore implements TokenStore {
  SecureTokenStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _accessKey = 'wizano.access_token';
  static const _refreshKey = 'wizano.refresh_token';
  static const _activeShopKey = 'wizano.active_shop_id';
  static const _userProfileKey = 'wizano.user_profile';

  @override
  Future<String?> readAccessToken() => _storage.read(key: _accessKey);

  @override
  Future<String?> readRefreshToken() => _storage.read(key: _refreshKey);

  @override
  Future<String?> readActiveShopId() => _storage.read(key: _activeShopKey);

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _storage.write(key: _accessKey, value: accessToken);
    await _storage.write(key: _refreshKey, value: refreshToken);
  }

  @override
  Future<void> saveActiveShopId(String? shopId) async {
    if (shopId == null) {
      await _storage.delete(key: _activeShopKey);
      return;
    }
    await _storage.write(key: _activeShopKey, value: shopId);
  }

  @override
  Future<void> saveUserProfile(String json) =>
      _storage.write(key: _userProfileKey, value: json);

  @override
  Future<String?> readUserProfile() => _storage.read(key: _userProfileKey);

  @override
  Future<void> clear() async {
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
    await _storage.delete(key: _activeShopKey);
    await _storage.delete(key: _userProfileKey);
  }
}

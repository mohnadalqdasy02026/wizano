import 'package:flutter_test/flutter_test.dart';
import 'package:shop_app/data/repositories/auth_repository.dart';
import 'package:shop_app/domain/entities/models.dart';
import 'package:shop_app/features/auth/auth_controller.dart';

class _FakeAuthRepository implements AuthRepository {
  bool loggedOut = false;
  bool offline = false;
  bool hasSession = true;
  User? cached;

  @override
  Future<void> logout() async {
    loggedOut = true;
  }

  @override
  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<AuthSession> register({
    required String displayName,
    required String email,
    required String password,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<User?> currentUser() async {
    if (offline) throw Exception('network down');
    return null;
  }

  @override
  Future<bool> hasStoredSession() async => hasSession;

  @override
  Future<User?> cachedUser() async => cached;

  @override
  Future<String?> readActiveShopId() async => null;

  @override
  Future<void> setActiveShopId(String? shopId) async {}
}

void main() {
  group('AuthController', () {
    test('logout يمسح البيانات المحلية', () async {
      var cleared = false;
      final controller = AuthController(
        repository: _FakeAuthRepository(),
        onLogout: () async => cleared = true,
      );

      await controller.logout();

      expect(cleared, isTrue);
      expect(controller.status, AuthStatus.unauthenticated);
    });

    test('فشل مسح البيانات لا يمنع الخروج', () async {
      final controller = AuthController(
        repository: _FakeAuthRepository(),
        onLogout: () async => throw Exception('db locked'),
      );

      await controller.logout();

      expect(controller.status, AuthStatus.unauthenticated);
    });

    test('دون اتصال تبقى الجلسة المحفوظة نشطة', () async {
      final repository = _FakeAuthRepository()
        ..offline = true
        ..cached = const User(
          id: 'u1',
          displayName: 'مالك',
          email: 'a@b.com',
        );
      final controller = AuthController(repository: repository);

      await controller.bootstrap();

      expect(controller.status, AuthStatus.authenticated);
      expect(controller.user?.displayName, 'مالك');
    });

    test('دون اتصال وبلا جلسة محفوظة: غير مُصادَق', () async {
      final repository = _FakeAuthRepository()
        ..offline = true
        ..hasSession = false;
      final controller = AuthController(repository: repository);

      await controller.bootstrap();

      expect(controller.status, AuthStatus.unauthenticated);
      expect(controller.user, isNull);
    });

    test('دون اتصال بجلسة محفوظة بلا ملف مستخدم: يبقى مُصادَقًا', () async {
      final repository = _FakeAuthRepository()..offline = true;
      final controller = AuthController(repository: repository);

      await controller.bootstrap();

      expect(controller.status, AuthStatus.authenticated);
      expect(controller.user, isNull);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/widgets.dart';
import '../auth/auth_controller.dart';
import '../shop/shop_controller.dart';

/// S01 — شاشة البداية: تحميل + فحص الجلسة والاتصال.
///
/// لا توجّه بنفسها؛ الجذر ([AppRoot]) يراقب [AuthController] ويبدّل الشاشة.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    final auth = context.read<AuthController>();
    await auth.bootstrap();
    if (!mounted || !auth.isAuthenticated) return;

    final shops = context.read<ShopController>();
    await shops.load();
    if (!mounted) return;
    final active = shops.active;
    if (active != null) {
      await auth.setActiveShopId(active.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            WizanoLogo(),
            SizedBox(height: 32),
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text(
              'جارٍ التهيئة...',
              style: TextStyle(color: Color(0xFF6B7280)),
            ),
          ],
        ),
      ),
    );
  }
}

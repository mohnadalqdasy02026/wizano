import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/widgets.dart';
import '../auth/auth_controller.dart';

/// S01 — شاشة البداية: تحميل + فحص الجلسة والاتصال.
///
/// لا توجّه بنفسها؛ الجذر ([AppRoot]) يراقب [AuthController] ويبدّل الشاشة،
/// وهو المسؤول عن تحميل المحلات بعد معرفة الجلسة (بما في ذلك المحل النشط
/// المحفوظ) — تحميلها هنا أيضًا كان يسبّب سباقًا يعيد شاشة «إعداد المحل».
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
    if (auth.status != AuthStatus.unknown) return;
    await auth.bootstrap();
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

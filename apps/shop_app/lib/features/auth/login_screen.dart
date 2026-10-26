import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/widgets.dart';
import '../../app/theme.dart';
import 'auth_controller.dart';
import 'register_screen.dart';

/// S02 — تسجيل الدخول (بريد + كلمة مرور).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _error = null);
    final auth = context.read<AuthController>();
    final error = await auth.login(
      email: _email.text.trim(),
      password: _password.text,
    );
    if (!mounted) return;
    setState(() => _error = error);
  }

  @override
  Widget build(BuildContext context) {
    final busy = context.watch<AuthController>().busy;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [WizanoColors.navy, WizanoColors.navyBright], begin: Alignment.topRight, end: Alignment.bottomLeft),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(34)),
              ),
              child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Image.asset('assets/images/app_icon.png', height: 48),
                  const SizedBox(width: 10),
                  const Text('WIZANO', textDirection: TextDirection.ltr, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 25, letterSpacing: 1.2)),
                ]),
                const SizedBox(height: 5),
                const Text('إدارة ديونك ومشترياتك بثقة', style: TextStyle(color: Color(0xFFDCEBFF), fontWeight: FontWeight.w600)),
              ]),
            ),
            Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Image.asset(
                  'assets/images/shop_login_hero.png',
                  height: 205,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
                const Align(alignment: Alignment.centerRight, child: Text('مرحبًا بعودتك', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900, color: WizanoColors.navy))),
                const SizedBox(height: 5),
                const Align(alignment: Alignment.centerRight, child: Text('سجّل دخولك للوصول إلى إدارة محلك.', style: TextStyle(color: WizanoColors.textMuted))),
                const SizedBox(height: 22),
                WizanoField(
                  label: 'البريد الإلكتروني',
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.username],
                  validator: (v) => (v == null || !v.contains('@'))
                      ? 'أدخل بريدًا إلكترونيًا صحيحًا'
                      : null,
                ),
                WizanoField(
                  label: 'كلمة المرور',
                  controller: _password,
                  obscure: true,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.password],
                  validator: (v) => (v == null || v.isEmpty)
                      ? 'أدخل كلمة المرور'
                      : null,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _error!,
                    style: const TextStyle(color: Color(0xFFDC2626)),
                  ),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 8),
                SizedBox(width: double.infinity, child: ElevatedButton.icon(
                  onPressed: busy ? null : _submit,
                  icon: busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.login_rounded),
                  label: Text(busy ? 'جارٍ الدخول...' : 'دخول إلى لوحة التحكم'),
                )),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const RegisterScreen(),
                            ),
                          ),
                  child: const Text('ليس لديك حساب؟ إنشاء حساب جديد'),
                ),
              ],
            ),
          ),
        ),
          ]),
        ),
      ),
    );
  }
}

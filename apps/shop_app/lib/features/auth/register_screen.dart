import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/widgets.dart';
import 'auth_controller.dart';

/// S03 — إنشاء حساب جديد (اسم العرض + بريد + كلمة مرور).
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _error = null);
    final auth = context.read<AuthController>();
    final error = await auth.register(
      displayName: _name.text.trim(),
      email: _email.text.trim(),
      password: _password.text,
    );
    if (!mounted) return;
    if (error == null) {
      // الجذر (AppRoot) سيبدّل إلى إعداد المحل فور تغيّر حالة المصادقة.
      Navigator.of(context).popUntil((route) => route.isFirst);
    } else {
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = context.watch<AuthController>().busy;
    return Scaffold(
      appBar: AppBar(title: const Text('إنشاء حساب')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                WizanoField(
                  label: 'الاسم',
                  controller: _name,
                  textInputAction: TextInputAction.next,
                  validator: (v) => (v == null || v.trim().length < 2)
                      ? 'أدخل اسمًا من حرفين على الأقل'
                      : null,
                ),
                WizanoField(
                  label: 'البريد الإلكتروني',
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  validator: (v) => (v == null || !v.contains('@'))
                      ? 'أدخل بريدًا إلكترونيًا صحيحًا'
                      : null,
                ),
                WizanoField(
                  label: 'كلمة المرور',
                  controller: _password,
                  obscure: true,
                  textInputAction: TextInputAction.done,
                  validator: (v) => (v == null || v.length < 8)
                      ? 'كلمة المرور 8 أحرف على الأقل'
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
                ElevatedButton(
                  onPressed: busy ? null : _submit,
                  child: busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('إنشاء الحساب'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

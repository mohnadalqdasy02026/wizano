import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/auth_controller.dart';
import '../profile/profile_screen.dart';
import '../shop/shop_controller.dart';
import '../speech/speech_controller.dart';
import '../speech/speech_engine.dart';
import '../speech/voice_model_screen.dart';

/// S28 — الإعدادات: الحساب، المحل، نموذج الصوت، الخروج.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  String _modelSubtitle(BuildContext context) {
    final status = context.watch<SpeechController>().modelManager.info.status;
    return switch (status) {
      ModelStatus.ready => 'جاهز — يعمل دون اتصال',
      ModelStatus.downloading => 'جارٍ التنزيل...',
      ModelStatus.verifying => 'جارٍ التحقق...',
      ModelStatus.error => 'فشل التنزيل — أعد المحاولة',
      ModelStatus.notDownloaded => 'غير محمّل — اضغط للتنزيل',
    };
  }

  @override
  Widget build(BuildContext context) {
    final shop = context.watch<ShopController>().active;

    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(
        children: [
          const _SectionHeader('الحساب'),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('الملف الشخصي'),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ProfileScreen()),
            ),
          ),
          const Divider(),
          const _SectionHeader('المحل'),
          ListTile(
            leading: const Icon(Icons.storefront_outlined),
            title: const Text('اسم المحل'),
            subtitle: Text(shop?.name ?? '—'),
          ),
          ListTile(
            leading: const Icon(Icons.payments_outlined),
            title: const Text('العملة'),
            subtitle: Text(shop?.currency ?? '—'),
          ),
          ListTile(
            leading: const Icon(Icons.public),
            title: const Text('المنطقة الزمنية'),
            subtitle: Text(shop?.timezone ?? '—'),
          ),
          const Divider(),
          const _SectionHeader('أخرى'),
          ListTile(
            leading: const Icon(Icons.record_voice_over_outlined),
            title: const Text('نموذج الصوت'),
            subtitle: Text(_modelSubtitle(context)),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const VoiceModelScreen()),
            ),
          ),
          const ListTile(
            leading: Icon(Icons.language_outlined),
            title: Text('اللغة'),
            subtitle: Text('العربية (افتراضي)'),
            enabled: false,
          ),
          ListTile(
            leading: const Icon(Icons.logout, color: Color(0xFFDC2626)),
            title: const Text(
              'تسجيل الخروج',
              style: TextStyle(color: Color(0xFFDC2626)),
            ),
            onTap: () => context.read<AuthController>().logout(),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: const TextStyle(
          color: Color(0xFF0B2A4A),
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

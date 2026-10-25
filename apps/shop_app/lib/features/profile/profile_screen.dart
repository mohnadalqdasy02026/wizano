import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../auth/auth_controller.dart';
import '../sync/sync_controller.dart';
import '../sync/sync_screen.dart';

/// S05 — الملف الشخصي للمستخدم: بيانات الحساب + الخروج.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final user = auth.user;
    final pendingCount = context.watch<SyncController>().pendingCount;

    return Scaffold(
      appBar: AppBar(title: const Text('الملف الشخصي')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 8),
          const CircleAvatar(
            radius: 40,
            backgroundColor: WizanoColors.navy,
            child: Icon(Icons.person, color: Colors.white, size: 44),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              user?.displayName ?? 'مستخدم',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: WizanoColors.textDark,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Card(
            child: Column(
              children: [
                _InfoRow(label: 'الاسم', value: user?.displayName ?? '—'),
                const Divider(height: 1),
                _InfoRow(label: 'البريد الإلكتروني', value: user?.email ?? '—'),
                if ((user?.phone ?? '').isNotEmpty) ...[
                  const Divider(height: 1),
                  _InfoRow(label: 'الهاتف', value: user!.phone!),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          Card(
            child: ListTile(
              leading: const Icon(Icons.sync, color: WizanoColors.navy),
              title: const Text('المزامنة'),
              subtitle: Text(
                pendingCount == 0
                    ? 'لا عمليات في الطابور'
                    : '$pendingCount عملية غير متزامنة',
                style: const TextStyle(
                  color: WizanoColors.textMuted,
                  fontSize: 13,
                ),
              ),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SyncScreen()),
              ),
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () => _confirmLogout(context),
            icon: const Icon(Icons.logout, color: WizanoColors.error),
            label: const Text(
              'تسجيل الخروج',
              style: TextStyle(color: WizanoColors.error),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تسجيل الخروج'),
        content: const Text('هل تريد تسجيل الخروج من حسابك؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('خروج'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await context.read<AuthController>().logout();
    }
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: WizanoColors.textMuted)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: WizanoColors.textDark,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

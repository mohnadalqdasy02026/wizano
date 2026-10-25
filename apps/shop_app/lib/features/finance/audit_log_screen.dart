import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../domain/entities/models.dart';
import 'finance_controller.dart';

/// S23 — سجل التدقيق: الإجراءات المالية الموثَّقة (المستخدم/الوقت/قبل-بعد).
class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({super.key});

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<FinanceController>().loadAuditLogs(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<FinanceController>();
    final logs = controller.auditLogs;

    return Scaffold(
      appBar: AppBar(title: const Text('سجل التدقيق')),
      body: _buildBody(controller, logs),
    );
  }

  Widget _buildBody(FinanceController controller, List<AuditEntry> logs) {
    if (controller.loading && logs.isEmpty) {
      return const LoadingState(message: 'جارٍ تحميل سجل التدقيق...');
    }
    if (controller.error != null && logs.isEmpty) {
      return ErrorState(
        message: controller.error!,
        onRetry: () => controller.loadAuditLogs(),
      );
    }
    if (logs.isEmpty) {
      return const EmptyState(message: 'لا توجد إجراءات موثَّقة بعد.');
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: logs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) => _AuditTile(entry: logs[i]),
    );
  }
}

class _AuditTile extends StatelessWidget {
  const _AuditTile({required this.entry});

  final AuditEntry entry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: WizanoColors.navy,
                  child: Icon(_icon, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _actionLabel,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: WizanoColors.textDark,
                    ),
                  ),
                ),
                Text(
                  _formatDate(entry.createdAt),
                  style: const TextStyle(
                    fontSize: 11,
                    color: WizanoColors.textMuted,
                  ),
                ),
              ],
            ),
            if (_detail != null) ...[
              const SizedBox(height: 8),
              Text(
                _detail!,
                style: const TextStyle(fontSize: 13, color: WizanoColors.textDark),
              ),
            ],
            if (_effect != null) ...[
              const SizedBox(height: 4),
              Text(
                'الأثر على الرصيد: $_effect',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: (_effectValue ?? 0) >= 0
                      ? WizanoColors.error
                      : WizanoColors.teal,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  IconData get _icon {
    switch (entry.action) {
      case 'purchase.return':
        return Icons.assignment_return_outlined;
      case 'purchase.cancel':
        return Icons.cancel_outlined;
      case 'adjustment.create':
        return Icons.tune;
      default:
        return Icons.receipt_long_outlined;
    }
  }

  String get _actionLabel {
    switch (entry.action) {
      case 'purchase.return':
        return 'مرتجع';
      case 'purchase.cancel':
        return 'إلغاء عملية';
      case 'adjustment.create':
        return 'تصحيح مالي';
      default:
        return entry.action;
    }
  }

  String? get _detail {
    final after = entry.after;
    if (after == null) return null;
    final reason = after['reason'];
    if (reason is String && reason.isNotEmpty) return 'السبب: $reason';
    return null;
  }

  int? get _effectValue {
    final effect = entry.after?['effect'] ?? entry.after?['amount'];
    if (effect is num) return effect.toInt();
    if (effect is String) return int.tryParse(effect);
    return null;
  }

  String? get _effect {
    final v = _effectValue;
    if (v == null) return null;
    return '${v >= 0 ? '+' : '−'}${v.abs()}';
  }

  String _formatDate(String iso) {
    try {
      return DateFormat('yyyy-MM-dd HH:mm')
          .format(DateTime.parse(iso).toLocal());
    } catch (_) {
      return iso;
    }
  }
}

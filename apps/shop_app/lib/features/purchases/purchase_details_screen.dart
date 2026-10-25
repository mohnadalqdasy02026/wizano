import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../domain/entities/models.dart';
import '../../domain/entities/sync_status.dart';

/// S15 — تفاصيل العملية بعد الحفظ: رقم العملية، القيم، والحالة.
class PurchaseDetailsScreen extends StatelessWidget {
  const PurchaseDetailsScreen({super.key, required this.purchase});

  final Purchase purchase;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تفاصيل العملية')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (purchase.syncStatus.isPending) ...[
            _SyncNotice(status: purchase.syncStatus),
            const SizedBox(height: 12),
          ],
          Card(
            child: Column(
              children: [
                _InfoRow(label: 'رقم العملية', value: '#${purchase.shopSeq}'),
                const Divider(height: 1),
                _InfoRow(
                  label: 'التاريخ',
                  value: _formatDate(purchase.occurredAt),
                ),
                const Divider(height: 1),
                _InfoRow(label: 'الحالة', value: _statusLabel(purchase)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                purchase.itemsText,
                style: const TextStyle(color: WizanoColors.textDark, height: 1.6),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                _InfoRow(
                  label: 'الإجمالي',
                  value: '${purchase.totalAmount}',
                ),
                const Divider(height: 1),
                _InfoRow(label: 'المدفوع', value: '${purchase.paidAmount}'),
                const Divider(height: 1),
                _AmountRow(
                  label: 'المتبقي',
                  value: '${purchase.remainingAmount}',
                ),
              ],
            ),
          ),
          if (purchase.notes != null && purchase.notes!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.notes),
                title: const Text('ملاحظات'),
                subtitle: Text(purchase.notes!),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// حالة العملية: العمليات المحلية غير المعتمدة لا تُوصف بـ«معتمد».
  String _statusLabel(Purchase purchase) {
    if (purchase.syncStatus.isPending) {
      return purchase.syncStatus == SyncStatus.failed
          ? 'غير معتمد — تعذّر الإرسال'
          : 'غير معتمد — محلي';
    }
    switch (purchase.status) {
      case 'active':
        return 'معتمد';
      case 'cancelled':
        return 'ملغى';
      default:
        return purchase.status;
    }
  }

  String _formatDate(String iso) {
    try {
      return DateFormat('yyyy-MM-dd HH:mm').format(DateTime.parse(iso).toLocal());
    } catch (_) {
      return iso;
    }
  }
}

class _SyncNotice extends StatelessWidget {
  const _SyncNotice({required this.status});

  final SyncStatus status;

  @override
  Widget build(BuildContext context) {
    final failed = status == SyncStatus.failed;
    final color = failed ? WizanoColors.error : WizanoColors.gold;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            failed ? Icons.error_outline : Icons.cloud_off_outlined,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              failed
                  ? 'تعذّر إرسال العملية إلى الخادم — أعد المحاولة لاحقًا.'
                  : 'العملية محفوظة على هذا الجهاز فقط ولم تُعتمد على الخادم بعد.',
              style: const TextStyle(color: WizanoColors.textDark, fontSize: 13),
            ),
          ),
        ],
      ),
    );
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
              style: const TextStyle(color: WizanoColors.textDark),
            ),
          ),
        ],
      ),
    );
  }
}

class _AmountRow extends StatelessWidget {
  const _AmountRow({required this.label, required this.value});

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
          Text(
            value,
            style: const TextStyle(
              color: WizanoColors.navy,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }
}

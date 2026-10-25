import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../domain/entities/models.dart';
import '../../domain/entities/sync_status.dart';

/// تفاصيل دفعة: المبلغ، التاريخ، الربط بالعملية، والرصيد بعدها.
class PaymentDetailsScreen extends StatelessWidget {
  const PaymentDetailsScreen({super.key, required this.payment});

  final Payment payment;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تفاصيل الدفعة')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (payment.syncStatus.isPending) ...[
            _SyncNotice(status: payment.syncStatus),
            const SizedBox(height: 12),
          ],
          Card(
            child: Column(
              children: [
                _InfoRow(
                  label: 'رقم الدفعة',
                  value: payment.shopSeq == null ? '—' : '#${payment.shopSeq}',
                ),
                const Divider(height: 1),
                _InfoRow(label: 'التاريخ', value: _formatDate(payment.paidAt)),
                const Divider(height: 1),
                _InfoRow(
                  label: 'مرتبطة بعملية',
                  value: payment.purchaseId == null ? 'دفعة عامة' : 'نعم',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                _AmountRow(label: 'المبلغ', value: '${payment.amount}'),
                if (payment.balanceAfter != null) ...[
                  const Divider(height: 1),
                  _InfoRow(
                    label: 'الرصيد بعد الدفعة',
                    value: '${payment.balanceAfter}',
                  ),
                ],
              ],
            ),
          ),
          if (payment.notes != null && payment.notes!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.notes),
                title: const Text('ملاحظات'),
                subtitle: Text(payment.notes!),
              ),
            ),
          ],
        ],
      ),
    );
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
                  ? 'تعذّر إرسال الدفعة إلى الخادم — أعد المحاولة لاحقًا.'
                  : 'الدفعة محفوظة على هذا الجهاز فقط ولم تُعتمد على الخادم بعد.',
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

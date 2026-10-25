import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../data/local/local_store.dart';
import '../../domain/entities/sync_status.dart';
import '../payments/payment_controller.dart';
import '../purchases/purchase_controller.dart';
import 'sync_controller.dart';

/// S08 — شاشة المزامنة: الطابور، الناجح، المتعثر (يحتاج تدخلًا)، آخر مزامنة.
class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<SyncController>().load();
    });
  }

  /// مزامنة الطابور ثم تحديث قوائم المشتريات والمدفوعات.
  Future<void> _syncNow() async {
    await context.read<SyncController>().syncNow();
    if (!mounted) return;
    await Future.wait([
      context.read<PurchaseController>().load(),
      context.read<PaymentController>().load(),
    ]);
  }

  /// إعادة محاولة عملية واحدة ثم تحديث القوائم.
  Future<void> _retry(String opId) async {
    await context.read<SyncController>().retry(opId);
    if (!mounted) return;
    await Future.wait([
      context.read<PurchaseController>().load(),
      context.read<PaymentController>().load(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SyncController>();

    return Scaffold(
      appBar: AppBar(title: const Text('المزامنة')),
      body: RefreshIndicator(
        onRefresh: () => controller.load(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _SummaryCard(controller: controller, onSync: _syncNow),
            const SizedBox(height: 12),
            if (controller.error != null) ...[
              ErrorState(message: controller.error!),
              const SizedBox(height: 12),
            ],
            _SectionTitle(title: 'في الطابور (${controller.pendingCount})'),
            const SizedBox(height: 8),
            if (controller.pending.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'لا عمليات في الطابور — كل شيء مُرسل.',
                    style: TextStyle(color: WizanoColors.textMuted),
                  ),
                ),
              )
            else
              ...controller.pending.map(
                (op) => _PendingTile(
                  operation: op,
                  onRetry: () => _retry(op.id),
                ),
              ),
            const SizedBox(height: 16),
            _SectionTitle(title: 'آخر المحاولات'),
            const SizedBox(height: 8),
            if (controller.attempts.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'لا محاولات مزامنة بعد.',
                    style: TextStyle(color: WizanoColors.textMuted),
                  ),
                ),
              )
            else
              ...controller.attempts.map((a) => _AttemptTile(attempt: a)),
            const SizedBox(height: 88),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.controller, required this.onSync});

  final SyncController controller;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.sync, color: WizanoColors.navy),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'حالة المزامنة',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: WizanoColors.textDark,
                    ),
                  ),
                ),
                if (controller.syncing)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'في الطابور: ${controller.pendingCount} — متعثر: ${controller.stuckCount}',
              style: const TextStyle(color: WizanoColors.textDark),
            ),
            const SizedBox(height: 4),
            Text(
              controller.lastSyncAt == null
                  ? 'لم تُجرَ مزامنة بعد'
                  : 'آخر مزامنة: ${_formatTime(controller.lastSyncAt!)}',
              style: const TextStyle(color: WizanoColors.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: controller.syncing ? null : onSync,
              icon: const Icon(Icons.cloud_upload_outlined),
              label: const Text('مزامنة الآن'),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime value) {
    try {
      return DateFormat('yyyy-MM-dd HH:mm').format(value.toLocal());
    } catch (_) {
      return value.toIso8601String();
    }
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.bold,
        color: WizanoColors.textDark,
      ),
    );
  }
}

class _PendingTile extends StatelessWidget {
  const _PendingTile({required this.operation, required this.onRetry});

  final QueuedOperation operation;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final failed = operation.status == SyncStatus.failed;
    final retrying = context.watch<SyncController>().retryingId == operation.id;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          failed ? Icons.error_outline : Icons.schedule,
          color: failed ? WizanoColors.error : WizanoColors.gold,
        ),
        title: Text(
          _title(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: WizanoColors.textDark),
        ),
        subtitle: Text(
          failed
              ? (operation.lastError ?? operation.status.label)
              : operation.status.label,
          style: TextStyle(
            color: failed ? WizanoColors.error : WizanoColors.textMuted,
            fontSize: 13,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'محاولات: ${operation.attempts}',
              style: const TextStyle(
                color: WizanoColors.textMuted,
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'إعادة محاولة',
              onPressed: retrying ? null : onRetry,
              icon: retrying
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, size: 20),
            ),
          ],
        ),
      ),
    );
  }

  /// وصف مختصر للعملية (الأصناف والمبلغ) بدل معرّف داخلي.
  String _title() {
    final payload = operation.payload;
    if (operation.opType == LocalOpType.purchase) {
      final items = payload['itemsText'] as String?;
      final total = payload['totalAmount'];
      if (items == null && total == null) return operation.opType.label;
      return '${items ?? operation.opType.label}'
          '${total == null ? '' : ' — $total'}';
    }
    final amount = payload['amount'];
    return amount == null ? operation.opType.label : 'دفعة — $amount';
  }
}

class _AttemptTile extends StatelessWidget {
  const _AttemptTile({required this.attempt});

  final SyncAttempt attempt;

  @override
  Widget build(BuildContext context) {
    final color = switch (attempt.status) {
      SyncAttemptStatus.sent => WizanoColors.teal,
      SyncAttemptStatus.failed => WizanoColors.error,
      SyncAttemptStatus.offline => WizanoColors.gold,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(Icons.history, color: color),
        title: Text(
          '${attempt.opType.label} — ${attempt.status.label}',
          style: const TextStyle(color: WizanoColors.textDark),
        ),
        subtitle: attempt.message == null
            ? null
            : Text(
                attempt.message!,
                style: const TextStyle(
                  color: WizanoColors.textMuted,
                  fontSize: 13,
                ),
              ),
        trailing: Text(
          _formatTime(attempt.createdAt),
          style: const TextStyle(color: WizanoColors.textMuted, fontSize: 12),
        ),
      ),
    );
  }

  String _formatTime(DateTime value) {
    try {
      return DateFormat('HH:mm').format(value.toLocal());
    } catch (_) {
      return value.toIso8601String();
    }
  }
}


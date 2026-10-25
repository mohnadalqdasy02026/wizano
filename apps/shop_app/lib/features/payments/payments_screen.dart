import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../domain/entities/models.dart';
import '../../domain/entities/sync_status.dart';
import 'payment_controller.dart';
import 'payment_details_screen.dart';
import 'payment_form_screen.dart';

/// S17 — سجل المدفوعات للمحل.
class PaymentsScreen extends StatelessWidget {
  const PaymentsScreen({super.key});

  Future<void> _openAdd(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PaymentFormScreen()),
    );
  }

  Future<void> _openDetails(BuildContext context, Payment p) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PaymentDetailsScreen(payment: p)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PaymentController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('المدفوعات'),
        actions: [
          if (controller.pendingCount > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: Text(
                  '${controller.pendingCount} غير متزامن',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAdd(context),
        icon: const Icon(Icons.payments_outlined),
        label: const Text('دفعة جديدة'),
      ),
      body: _buildBody(context, controller),
    );
  }

  Widget _buildBody(BuildContext context, PaymentController controller) {
    if (controller.loading && controller.payments.isEmpty) {
      return const LoadingState(message: 'جارٍ تحميل المدفوعات...');
    }
    if (controller.error != null && controller.payments.isEmpty) {
      return ErrorState(
        message: controller.error!,
        onRetry: () => controller.load(),
      );
    }
    if (controller.payments.isEmpty) {
      // السحب للتحديث متاح حتى في حالة الفراغ (لتحديث القائمة/الطابور).
      return RefreshIndicator(
        onRefresh: () => controller.load(),
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: EmptyState(
                message: 'لا مدفوعات بعد — سجّل أول دفعة.',
                icon: Icons.payments_outlined,
                actionLabel: 'تسجيل دفعة',
                onAction: () => _openAdd(context),
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        if (controller.pendingCount > 0)
          Container(
            width: double.infinity,
            color: WizanoColors.gold.withValues(alpha: 0.16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Text(
              'يوجد ${controller.pendingCount} عملية محلية غير متزامنة',
              style: const TextStyle(
                color: WizanoColors.navy,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => controller.load(),
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 88),
              itemCount: controller.payments.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final p = controller.payments[i];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: WizanoColors.teal,
                    child: Text(
                      p.shopSeq == null ? '—' : '#${p.shopSeq}',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                  title: Text('دفعة ${p.amount}',
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    p.purchaseId == null ? 'دفعة عامة على الحساب' : 'مرتبطة بعملية',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (p.syncStatus.isPending)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: (p.syncStatus == SyncStatus.failed
                                    ? WizanoColors.error
                                    : WizanoColors.gold)
                                .withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            p.syncStatus.label,
                            style: TextStyle(
                              fontSize: 11,
                              color: p.syncStatus == SyncStatus.failed
                                  ? WizanoColors.error
                                  : WizanoColors.navy,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      const Icon(Icons.chevron_left),
                    ],
                  ),
                  onTap: () => _openDetails(context, p),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

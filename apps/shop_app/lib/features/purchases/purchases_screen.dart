import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../domain/entities/models.dart';
import '../../domain/entities/sync_status.dart';
import 'purchase_controller.dart';
import 'purchase_details_screen.dart';
import 'purchase_form_screen.dart';

/// S13-entry — قائمة المشتريات الآجلة للمحل.
class PurchasesScreen extends StatelessWidget {
  const PurchasesScreen({super.key});

  Future<void> _openAdd(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PurchaseFormScreen()),
    );
  }

  Future<void> _openDetails(BuildContext context, Purchase p) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PurchaseDetailsScreen(purchase: p)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PurchaseController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('المشتريات'),
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
        icon: const Icon(Icons.add_shopping_cart),
        label: const Text('عملية جديدة'),
      ),
      body: _buildBody(context, controller),
    );
  }

  Widget _buildBody(BuildContext context, PurchaseController controller) {
    if (controller.loading && controller.purchases.isEmpty) {
      return const LoadingState(message: 'جارٍ تحميل المشتريات...');
    }
    if (controller.error != null && controller.purchases.isEmpty) {
      return ErrorState(
        message: controller.error!,
        onRetry: () => controller.load(),
      );
    }
    if (controller.purchases.isEmpty) {
      // السحب للتحديث متاح حتى في حالة الفراغ (لتحديث القائمة/الطابور).
      return RefreshIndicator(
        onRefresh: () => controller.load(),
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: EmptyState(
                message: 'لا مشتريات بعد — سجّل أول عملية.',
                icon: Icons.receipt_long_outlined,
                actionLabel: 'تسجيل عملية',
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
              itemCount: controller.purchases.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final p = controller.purchases[i];
                return TweenAnimationBuilder<double>(
                  key: ValueKey(p.id),
                  duration: const Duration(milliseconds: 260),
                  tween: Tween(begin: 0, end: 1),
                  builder: (_, value, child) => Opacity(
                    opacity: value,
                    child: Transform.translate(
                      offset: Offset(0, 12 * (1 - value)),
                      child: child,
                    ),
                  ),
                  child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: WizanoColors.navy,
                    child: Text(
                      '#${p.shopSeq}',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                  title: Text(p.itemsText, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('الإجمالي ${p.totalAmount} — متبقي ${p.remainingAmount}'),
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
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

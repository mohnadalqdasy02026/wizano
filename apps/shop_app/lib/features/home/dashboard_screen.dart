import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../domain/entities/models.dart';
import '../../domain/entities/sync_status.dart';
import '../auth/auth_controller.dart';
import '../customers/customer_controller.dart';
import '../payments/payment_controller.dart';
import '../purchases/purchase_controller.dart';
import '../purchases/purchase_details_screen.dart';
import '../payments/payment_details_screen.dart';
import '../shop/shop_controller.dart';
import '../settings/settings_screen.dart';
import '../sync/sync_controller.dart';
import '../sync/sync_screen.dart';

/// S06 — لوحة التحكم: ملخص (مستحقات اليوم، إجمالي الديون، آخر العمليات، حالة المزامنة).
///
/// **قاعدة:** الإجماليات المالية تُحسب من العمليات **المعتمدة فقط**؛ العمليات
/// المحلية غير المرسلة تُعرض كوسم صريح ولا تُحتسب في الديون (docs/01 §6.2).
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final auth = context.read<AuthController>();
    final user = auth.user;
    if (user != null) {
      await context.read<ShopController>().load();
    }
    if (!mounted) return;
    final shopId = context.read<ShopController>().active?.id;
    if (shopId == null) return;
    final customers = context.read<CustomerController>();
    final purchases = context.read<PurchaseController>();
    final payments = context.read<PaymentController>();
    await Future.wait([
      customers.load(),
      purchases.load(),
      payments.load(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final shops = context.watch<ShopController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('لوحة التحكم'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'الإعدادات',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _buildBody(auth, shops),
      ),
    );
  }

  Widget _buildBody(AuthController auth, ShopController shops) {
    if (shops.loading && shops.shops.isEmpty) {
      return const LoadingState(message: 'جارٍ تحميل بيانات المحل...');
    }
    if (shops.error != null && shops.shops.isEmpty) {
      return ListView(
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.2),
          ErrorState(message: shops.error!, onRetry: _load),
        ],
      );
    }
    if (!shops.hasShop) {
      return const EmptyState(
        message: 'لا يوجد محل مرتبط بحسابك.',
        icon: Icons.storefront_outlined,
      );
    }

    final shop = shops.active!;
    final purchaseController = context.watch<PurchaseController>();
    final purchases = purchaseController.purchases;
    final payments = context.watch<PaymentController>().payments;
    final customers = context.watch<CustomerController>().customers;

    // الإجماليات تُحسب من العمليات المعتمدة فقط.
    final approved = purchases.where((p) => p.syncStatus == SyncStatus.synced);
    final totalDebt = approved.fold<int>(0, (sum, p) => sum + p.remainingAmount);
    final todayDebt = approved
        .where((p) => _isToday(p.occurredAt))
        .fold<int>(0, (sum, p) => sum + p.remainingAmount);
    final localCount = purchases.where((p) => p.syncStatus.isPending).length +
        payments.where((p) => p.syncStatus.isPending).length;

    // دون اتصال: القائمة محلية فقط، فالرقم ليس إجمالي الديون الحقيقي.
    final totalsKnown = purchaseController.fromServer;
    final debtLabel = totalsKnown ? '$totalDebt' : '—';
    final todayLabel = totalsKnown ? '$todayDebt' : '—';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const CircleAvatar(
                  backgroundColor: WizanoColors.navy,
                  child: Icon(Icons.storefront, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        shop.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: WizanoColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'مرحبًا، ${auth.user?.displayName ?? ''}',
                        style: const TextStyle(color: WizanoColors.textMuted),
                      ),
                      Text(
                        'العملة: ${shop.currency} — ${shop.timezone}',
                        style: const TextStyle(
                          color: WizanoColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _SummaryGrid(
          todayDebt: todayLabel,
          totalDebt: debtLabel,
          customersCount: customers.length,
        ),
        if (!totalsKnown) ...[
          const SizedBox(height: 8),
          const Text(
            'الأرقام المالية غير معروفة دون اتصال — اعتمد على كشف الحساب من الخادم.',
            style: TextStyle(color: WizanoColors.gold, fontSize: 12),
          ),
        ],
        if (localCount > 0) ...[
          const SizedBox(height: 8),
          Text(
            '$localCount عملية محلية غير متزامنة — لم تُحتسب في الإجماليات.',
            style: const TextStyle(color: WizanoColors.gold, fontSize: 12),
          ),
        ],
        const SizedBox(height: 16),
        const _SyncStatusCard(),
        const SizedBox(height: 16),
        const Text(
          'آخر العمليات',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: WizanoColors.textDark,
          ),
        ),
        const SizedBox(height: 8),
        _RecentOperations(
          purchases: purchases,
          payments: payments,
          customers: customers,
        ),
      ],
    );
  }

  bool _isToday(String iso) {
    try {
      final when = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      return when.year == now.year &&
          when.month == now.month &&
          when.day == now.day;
    } catch (_) {
      return false;
    }
  }
}

/// شبكة الملخص — القيم من العمليات المعتمدة فقط.
class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({
    required this.todayDebt,
    required this.totalDebt,
    required this.customersCount,
  });

  final String todayDebt;
  final String totalDebt;
  final int customersCount;

  @override
  Widget build(BuildContext context) {
    final cells = [
      _SummaryCell(
        label: 'مستحقات اليوم',
        icon: Icons.today_outlined,
        value: todayDebt,
      ),
      _SummaryCell(
        label: 'إجمالي الديون',
        icon: Icons.account_balance_wallet_outlined,
        value: totalDebt,
      ),
      _SummaryCell(
        label: 'العملاء',
        icon: Icons.people_outline,
        value: '$customersCount',
      ),
    ];
    return Row(
      children: cells
          .map(
            (c) => Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        Icon(c.icon, color: WizanoColors.teal),
                        const SizedBox(height: 8),
                        Text(
                          c.value,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: WizanoColors.textDark,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          c.label,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12,
                            color: WizanoColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

/// حالة المزامنة — ملخص سريع يفتح شاشة S08.
class _SyncStatusCard extends StatelessWidget {
  const _SyncStatusCard();

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncController>();
    final pending = sync.pendingCount;
    final color = pending == 0 ? WizanoColors.teal : WizanoColors.gold;

    return Card(
      child: ListTile(
        leading: Icon(Icons.sync, color: color),
        title: const Text(
          'حالة المزامنة',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: WizanoColors.textDark,
          ),
        ),
        subtitle: Text(
          pending == 0
              ? 'كل العمليات مُرسلة'
              : '$pending عملية غير متزامنة — لم تُرسل بعد',
          style: const TextStyle(color: WizanoColors.textMuted, fontSize: 13),
        ),
        trailing: const Icon(Icons.chevron_left),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SyncScreen()),
        ),
      ),
    );
  }
}

/// آخر العمليات — مشتريات ومدفوعات مدموجة، مع وسم صريح للمحلية.
class _RecentOperations extends StatelessWidget {
  const _RecentOperations({
    required this.purchases,
    required this.payments,
    required this.customers,
  });

  final List<Purchase> purchases;
  final List<Payment> payments;
  final List<Customer> customers;

  @override
  Widget build(BuildContext context) {
    final names = {
      for (final c in customers) c.id: c.displayName,
    };
    final items = <_RecentOp>[
      for (final p in purchases)
        _RecentOp(
          date: p.occurredAt,
          title: p.itemsText,
          subtitle: names[p.customerId] ?? 'عميل',
          amount: p.totalAmount,
          status: p.syncStatus,
          kind: _RecentKind.purchase,
          payload: p,
        ),
      for (final p in payments)
        _RecentOp(
          date: p.paidAt,
          title: 'دفعة',
          subtitle: names[p.customerId] ?? 'عميل',
          amount: p.amount,
          status: p.syncStatus,
          kind: _RecentKind.payment,
          payload: p,
        ),
    ]..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    if (items.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: EmptyState(
            message: 'لا عمليات مسجّلة بعد.',
            icon: Icons.receipt_long_outlined,
          ),
        ),
      );
    }

    return Card(
      child: Column(
        children: [
          for (final item in items.take(5))
            ListTile(
              leading: Icon(
                item.kind == _RecentKind.purchase
                    ? Icons.receipt_long_outlined
                    : Icons.payments_outlined,
                color: WizanoColors.navy,
              ),
              title: Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: WizanoColors.textDark),
              ),
              subtitle: Text(
                item.subtitle,
                style: const TextStyle(
                  color: WizanoColors.textMuted,
                  fontSize: 13,
                ),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${item.amount}',
                    style: const TextStyle(
                      color: WizanoColors.navy,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (item.status.isPending) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: WizanoColors.gold.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        item.status.label,
                        style: const TextStyle(
                          fontSize: 11,
                          color: WizanoColors.navy,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              onTap: () => _openDetails(context, item),
            ),
        ],
      ),
    );
  }

  void _openDetails(BuildContext context, _RecentOp item) {
    if (item.kind == _RecentKind.purchase) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PurchaseDetailsScreen(purchase: item.payload as Purchase),
        ),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PaymentDetailsScreen(payment: item.payload as Payment),
        ),
      );
    }
  }
}

enum _RecentKind { purchase, payment }

class _RecentOp {
  const _RecentOp({
    required this.date,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.status,
    required this.kind,
    required this.payload,
  });

  final String date;
  final String title;
  final String subtitle;
  final int amount;
  final SyncStatus status;
  final _RecentKind kind;
  final Object payload;

  DateTime get timestamp {
    try {
      return DateTime.parse(date);
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }
}

class _SummaryCell {
  const _SummaryCell({
    required this.label,
    required this.icon,
    required this.value,
  });

  final String label;
  final IconData icon;
  final String value;
}


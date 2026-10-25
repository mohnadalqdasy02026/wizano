import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../domain/entities/models.dart';
import '../finance/adjustment_form_screen.dart';
import '../finance/audit_log_screen.dart';
import 'operation_details_screen.dart';
import 'statement_controller.dart';

/// S18 — كشف حساب العميل: الإجماليات + العمليات زمنيًا مع الرصيد الجاري + تصفية.
class StatementScreen extends StatefulWidget {
  const StatementScreen({
    super.key,
    required this.shopId,
    required this.customerId,
    required this.customerName,
  });

  final String shopId;
  final String customerId;
  final String customerName;

  @override
  State<StatementScreen> createState() => _StatementScreenState();
}

class _StatementScreenState extends State<StatementScreen> {
  // نوع التصفية: all / purchase / payment.
  String _type = 'all';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  Future<void> _reload() async {
    await context.read<StatementController>().load(
          widget.shopId,
          widget.customerId,
          type: _type,
        );
  }

  void _setType(String type) {
    if (_type == type) return;
    setState(() => _type = type);
    _reload();
  }

  Future<void> _openAdjustment() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdjustmentFormScreen(
          customerId: widget.customerId,
          customerName: widget.customerName,
        ),
      ),
    );
    if (result != null) await _reload();
  }

  void _openAuditLog() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AuditLogScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<StatementController>();
    final statement = controller.statement;

    return Scaffold(
      appBar: AppBar(
        title: const Text('كشف الحساب'),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'تصحيح مالي',
            onPressed: _openAdjustment,
          ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'سجل التدقيق',
            onPressed: _openAuditLog,
          ),
        ],
      ),
      body: Column(
        children: [
          _Header(
            customerName: widget.customerName,
            statement: statement,
          ),
          _FilterBar(selected: _type, onChanged: _setType),
          const Divider(height: 1),
          Expanded(child: _buildBody(controller, statement)),
        ],
      ),
    );
  }

  Widget _buildBody(StatementController controller, CustomerStatement? statement) {
    if (controller.loading && statement == null) {
      return const LoadingState(message: 'جارٍ تحميل كشف الحساب...');
    }
    if (controller.error != null && statement == null) {
      return ErrorState(message: controller.error!, onRetry: _reload);
    }
    final entries = statement?.entries ?? const [];
    if (entries.isEmpty) {
      return const EmptyState(message: 'لا توجد عمليات مطابقة.');
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: entries.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final entry = entries[i];
        return _EntryTile(
          entry: entry,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => OperationDetailsScreen(
                entry: entry,
                shopId: widget.shopId,
                customerId: widget.customerId,
                customerName: widget.customerName,
                onChanged: _reload,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.customerName, required this.statement});

  final String customerName;
  final CustomerStatement? statement;

  @override
  Widget build(BuildContext context) {
    final s = statement;
    return Container(
      width: double.infinity,
      color: WizanoColors.navy,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            customerName,
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _SummaryRow(
            label: 'إجمالي المشتريات',
            value: s == null ? '—' : '${s.totalPurchases}',
          ),
          const SizedBox(height: 6),
          _SummaryRow(
            label: 'إجمالي المدفوعات',
            value: s == null ? '—' : '${s.totalPayments}',
          ),
          const SizedBox(height: 6),
          _SummaryRow(
            label: 'إجمالي المرتجعات',
            value: s == null ? '—' : '${s.totalReturns}',
          ),
          const SizedBox(height: 6),
          _SummaryRow(
            label: 'صافي التصحيحات',
            value: s == null ? '—' : '${s.totalAdjustments}',
          ),
          const Divider(color: Colors.white24, height: 20),
          _SummaryRow(
            label: 'الرصيد المستحق',
            value: s == null ? '—' : '${s.balance}',
            emphasize: true,
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: emphasize ? Colors.white : Colors.white70,
            fontWeight: emphasize ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: emphasize ? WizanoColors.gold : Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: emphasize ? 20 : 15,
          ),
        ),
      ],
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.selected, required this.onChanged});

  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    const options = [
      ('all', 'الكل'),
      ('purchase', 'مشتريات'),
      ('payment', 'مدفوعات'),
      ('return', 'مرتجعات'),
      ('adjustment', 'تصحيحات'),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          for (final (value, label) in options) ...[
            ChoiceChip(
              label: Text(label),
              selected: selected == value,
              onSelected: (_) => onChanged(value),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry, required this.onTap});

  final StatementEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: _accent,
          child: Icon(_icon, color: Colors.white, size: 20),
        ),
        title: Text(
          _typeLabel,
          style: const TextStyle(fontWeight: FontWeight.bold, color: WizanoColors.textDark),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (entry.description.isNotEmpty)
              Text(
                entry.description,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            Text(
              _formatDate(entry.occurredAt),
              style: const TextStyle(fontSize: 12, color: WizanoColors.textMuted),
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${entry.effect > 0 ? '+' : '−'}${entry.effect.abs()}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: entry.effect >= 0 ? WizanoColors.error : WizanoColors.teal,
              ),
            ),
            Text(
              'رصيد: ${entry.balanceAfter}',
              style: const TextStyle(fontSize: 11, color: WizanoColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  String get _typeLabel {
    switch (entry.type) {
      case 'purchase':
        return 'شراء';
      case 'return':
        return 'مرتجع';
      case 'adjustment':
        return entry.adjustmentKind == 'cancellation' ? 'إلغاء' : 'تصحيح';
      default:
        return 'دفعة';
    }
  }

  IconData get _icon {
    switch (entry.type) {
      case 'purchase':
        return Icons.shopping_bag_outlined;
      case 'return':
        return Icons.assignment_return_outlined;
      case 'adjustment':
        return Icons.tune;
      default:
        return Icons.payments_outlined;
    }
  }

  Color get _accent {
    switch (entry.type) {
      case 'purchase':
        return WizanoColors.navy;
      case 'return':
        return WizanoColors.gold;
      case 'adjustment':
        return entry.adjustmentKind == 'cancellation'
            ? WizanoColors.error
            : WizanoColors.navy;
      default:
        return WizanoColors.teal;
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

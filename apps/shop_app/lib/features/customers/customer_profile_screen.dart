import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../domain/entities/models.dart';
import '../shop/shop_controller.dart';
import '../statements/statement_controller.dart';
import '../statements/statement_screen.dart';
import 'customer_controller.dart';
import 'customer_form_screen.dart';
import '../messages/customer_messages_screen.dart';

/// S11 — ملف العميل: بياناته + رصيده المحسوب + إجراءات (تعديل/أرشفة/دعوة/كشف حساب).
/// S12 — ربط العميل بالمحل مُدمج هنا عبر زر «رمز الدعوة».
class CustomerProfileScreen extends StatefulWidget {
  const CustomerProfileScreen({super.key, required this.customerId});

  final String customerId;

  @override
  State<CustomerProfileScreen> createState() => _CustomerProfileScreenState();
}

class _CustomerProfileScreenState extends State<CustomerProfileScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadBalance());
  }

  String? get _shopId => context.read<ShopController>().active?.id;

  Future<void> _loadBalance() async {
    final shopId = _shopId;
    if (shopId == null || !mounted) return;
    await context
        .read<StatementController>()
        .load(shopId, widget.customerId);
  }

  Future<void> _openStatement(Customer customer) async {
    final shopId = _shopId;
    if (shopId == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StatementScreen(
          shopId: shopId,
          customerId: customer.id,
          customerName: customer.displayName,
        ),
      ),
    );
    // تعكس الرصيد بعد العودة (قد تكون عمليات جديدة أُضيفت).
    if (mounted) await _loadBalance();
  }

  Future<void> _openEdit(Customer customer) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CustomerFormScreen(customer: customer)),
    );
  }

  Future<void> _openMessages(Customer customer) async {
    final shopId = _shopId;
    if (shopId == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CustomerMessagesScreen(
          shopId: shopId,
          customerId: customer.id,
          customerName: customer.displayName,
        ),
      ),
    );
  }

  Future<void> _confirmArchive(Customer customer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('أرشفة العميل'),
        content: Text('هل تريد أرشفة «${customer.displayName}»؟ '
            'سيختفي من القائمة دون حذف عملياته.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('أرشفة'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final error = await context.read<CustomerController>().archive(customer.id);
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  Future<void> _showInvite(Customer customer) async {
    final invite = await context.read<CustomerController>().invite(customer.id);
    if (!mounted) return;
    if (invite == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر إنشاء رمز الدعوة.')),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('رمز الدعوة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('شارك هذا الرمز مع العميل ليربط حسابه بهذا المحل:'),
            const SizedBox(height: 12),
            SelectableText(
              invite.code,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                letterSpacing: 4,
                color: WizanoColors.navy,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'صالح حتى: ${_formatDate(invite.expiresAt)}',
              style: const TextStyle(fontSize: 12, color: WizanoColors.textMuted),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: invite.code));
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('تم نسخ الرمز.')),
                );
              }
            },
            icon: const Icon(Icons.copy),
            label: const Text('نسخ'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  String _formatDate(String iso) {
    try {
      return DateFormat('yyyy-MM-dd').format(DateTime.parse(iso).toLocal());
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<CustomerController>();
    final statementController = context.watch<StatementController>();
    final statement = statementController.statement;
    final statementLoading = statementController.loading;
    final customer = _find(controller);

    if (customer == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('ملف العميل')),
        body: const EmptyState(message: 'العميل غير متاح.'),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('ملف العميل'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'تعديل',
            onPressed: () => _openEdit(customer),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'أرشفة',
            onPressed: () => _confirmArchive(customer),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 8),
          CircleAvatar(
            radius: 36,
            backgroundColor: WizanoColors.navy,
            child: Text(
              customer.displayName.characters.first,
              style: const TextStyle(color: Colors.white, fontSize: 28),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              customer.displayName,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: WizanoColors.textDark,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Card(
            child: Column(
              children: [
                _InfoRow(label: 'الهاتف', value: customer.phone ?? '—'),
                const Divider(height: 1),
                _InfoRow(label: 'ملاحظات', value: customer.notes ?? '—'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // الرصيد المحسوب من السجلات المالية (مشتريات − مدفوعات).
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'الرصيد المستحق',
                    style: TextStyle(color: WizanoColors.textMuted),
                  ),
                  if (statementLoading)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Text(
                      statement == null ? '—' : '${statement.balance}',
                      style: const TextStyle(
                        color: WizanoColors.navy,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => _openStatement(customer),
            icon: const Icon(Icons.receipt_long_outlined),
            label: const Text('كشف الحساب'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _openMessages(customer),
            icon: const Icon(Icons.forum_outlined),
            label: const Text('مراسلة العميل'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _showInvite(customer),
            icon: const Icon(Icons.qr_code_2),
            label: const Text('رمز دعوة لربط العميل بالمحل'),
          ),
        ],
      ),
    );
  }

  Customer? _find(CustomerController controller) {
    for (final c in controller.customers) {
      if (c.id == widget.customerId) return c;
    }
    return null;
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

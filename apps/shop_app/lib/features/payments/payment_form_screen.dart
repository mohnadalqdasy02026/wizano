import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/widgets.dart';
import '../../core/connectivity.dart';
import '../customers/customer_controller.dart';
import '../purchases/purchase_controller.dart';
import 'payment_controller.dart';
import 'payment_details_screen.dart';

/// S16 — تسجيل دفعة (عميل، مبلغ، ربط اختياري بعملية، ملاحظات).
class PaymentFormScreen extends StatefulWidget {
  const PaymentFormScreen({super.key, this.initialCustomerId, this.initialPurchaseId});

  /// عميل مبدئي (عند القدوم من كشف/تفاصيل عملية).
  final String? initialCustomerId;

  /// عملية مبدئية لربط الدفعة بها.
  final String? initialPurchaseId;

  @override
  State<PaymentFormScreen> createState() => _PaymentFormScreenState();
}

class _PaymentFormScreenState extends State<PaymentFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _notes = TextEditingController();
  String? _customerId;
  String? _purchaseId;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _customerId = widget.initialCustomerId;
    _purchaseId = widget.initialPurchaseId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // تحميل مشتريات العميل المبدئي لتمكين ربط الدفعة بعملية.
      final purchases = context.read<PurchaseController>();
      if (_customerId != null) purchases.load(customerId: _customerId);
    });
  }

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  int get _amountValue => int.tryParse(_amount.text.trim()) ?? 0;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_customerId == null) {
      setState(() => _error = 'اختر العميل أولًا.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final result = await context.read<PaymentController>().add(
          customerId: _customerId!,
          amount: _amountValue,
          purchaseId: _purchaseId,
          notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        );

    if (!mounted) return;
    setState(() => _busy = false);
    if (result.error != null) {
      setState(() => _error = result.error);
      return;
    }

    if (result.savedLocally) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تعذّر الوصول إلى الخادم — حُفظت الدفعة محليًا وستُرسل عند توفّر الاتصال.',
          ),
        ),
      );
    }

    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => PaymentDetailsScreen(payment: result.payment!),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final customers = context.watch<CustomerController>().customers;
    final purchases = context.watch<PurchaseController>().purchases
        .where((p) => p.customerId == _customerId && p.remainingAmount > 0)
        .toList();
    final offline = context.watch<ConnectivityMonitor>().offline;

    return Scaffold(
      appBar: AppBar(title: const Text('تسجيل دفعة')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (offline) ...[
                  const OfflineNotice(
                    message:
                        'لا يوجد اتصال بالخادم — ستُحفظ الدفعة محليًا وتُرسل لاحقًا.',
                  ),
                  const SizedBox(height: 14),
                ],
                DropdownButtonFormField<String>(
                  initialValue: _customerId,
                  decoration: const InputDecoration(
                    labelText: 'العميل',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
                  ),
                  items: customers
                      .map(
                        (c) => DropdownMenuItem(
                          value: c.id,
                          child: Text(c.displayName),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    setState(() {
                      _customerId = v;
                      _purchaseId = null;
                    });
                    if (v != null) {
                      context.read<PurchaseController>().load(customerId: v);
                    }
                  },
                  validator: (v) => v == null ? 'اختر العميل' : null,
                ),
                const SizedBox(height: 14),
                WizanoField(
                  label: 'المبلغ',
                  controller: _amount,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  validator: (v) {
                    final n = int.tryParse((v ?? '').trim());
                    if (n == null) return 'أدخل رقمًا صحيحًا';
                    if (n <= 0) return 'المبلغ يجب أن يكون أكبر من صفر';
                    return null;
                  },
                ),
                if (_customerId != null && purchases.isNotEmpty)
                  DropdownButtonFormField<String?>(
                    initialValue: _purchaseId,
                    decoration: const InputDecoration(
                      labelText: 'ربط بعملية (اختياري)',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                      ),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('دفعة عامة على الحساب'),
                      ),
                      ...purchases.map(
                        (p) => DropdownMenuItem<String?>(
                          value: p.id,
                          child: Text('#${p.shopSeq} — متبقي ${p.remainingAmount}'),
                        ),
                      ),
                    ],
                    onChanged: (v) => setState(() => _purchaseId = v),
                  ),
                if (_customerId != null && purchases.isNotEmpty)
                  const SizedBox(height: 14),
                WizanoField(
                  label: 'ملاحظات (اختياري)',
                  controller: _notes,
                  textInputAction: TextInputAction.done,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _error!,
                    style: const TextStyle(color: Color(0xFFDC2626)),
                  ),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('تسجيل الدفعة'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

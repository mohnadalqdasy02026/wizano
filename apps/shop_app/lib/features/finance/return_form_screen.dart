import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/widgets.dart';
import 'finance_controller.dart';

/// S20 — تسجيل مرتجع مرتبط بعملية شراء: المبلغ + سبب اختياري.
///
/// يُفتح من تفاصيل عملية شراء (يحمل معرّف العملية والمتبقي الأعلى المسموح).
class ReturnFormScreen extends StatefulWidget {
  const ReturnFormScreen({
    super.key,
    required this.purchaseId,
    this.purchaseLabel,
    this.maxAmount,
  });

  final String purchaseId;

  /// بيان العملية (مثل «#12 — شراء») للعرض.
  final String? purchaseLabel;

  /// الحد الأعلى المسموح للمرتجع (متبقي العملية) إن عُرف.
  final int? maxAmount;

  @override
  State<ReturnFormScreen> createState() => _ReturnFormScreenState();
}

class _ReturnFormScreenState extends State<ReturnFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _reason = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  int get _amountValue => int.tryParse(_amount.text.trim()) ?? 0;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    final result = await context.read<FinanceController>().addReturn(
          purchaseId: widget.purchaseId,
          amount: _amountValue,
          reason: _reason.text.trim().isEmpty ? null : _reason.text.trim(),
        );

    if (!mounted) return;
    setState(() => _busy = false);
    if (result.error != null) {
      setState(() => _error = result.error);
      return;
    }
    Navigator.of(context).pop(result.returnEntry);
  }

  @override
  Widget build(BuildContext context) {
    final max = widget.maxAmount;
    return Scaffold(
      appBar: AppBar(title: const Text('تسجيل مرتجع')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.purchaseLabel != null)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.shopping_bag_outlined),
                      title: Text(widget.purchaseLabel!),
                      subtitle: max == null
                          ? null
                          : Text('المتبقي على العملية: $max'),
                    ),
                  ),
                const SizedBox(height: 14),
                WizanoField(
                  label: 'قيمة المرتجع',
                  controller: _amount,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  validator: (v) {
                    final n = int.tryParse((v ?? '').trim());
                    if (n == null) return 'أدخل رقمًا صحيحًا';
                    if (n <= 0) return 'القيمة يجب أن تكون أكبر من صفر';
                    if (max != null && n > max) {
                      return 'تتجاوز المتبقي على العملية ($max)';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                WizanoField(
                  label: 'السبب (اختياري)',
                  controller: _reason,
                  textInputAction: TextInputAction.done,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 4),
                  Text(_error!, style: const TextStyle(color: Color(0xFFDC2626))),
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
                      : const Text('تسجيل المرتجع'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

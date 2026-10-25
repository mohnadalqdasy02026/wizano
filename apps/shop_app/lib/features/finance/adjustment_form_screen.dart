import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../app/widgets.dart';
import 'finance_controller.dart';

/// S21 — تسجيل تصحيح مالي لعميل: مبلغ (موجب يزيد/سالب يخصم) + سبب إلزامي.
class AdjustmentFormScreen extends StatefulWidget {
  const AdjustmentFormScreen({
    super.key,
    required this.customerId,
    this.customerName,
    this.relatedPurchaseId,
  });

  final String customerId;
  final String? customerName;

  /// ربط اختياري بعملية محددة.
  final String? relatedPurchaseId;

  @override
  State<AdjustmentFormScreen> createState() => _AdjustmentFormScreenState();
}

class _AdjustmentFormScreenState extends State<AdjustmentFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _reason = TextEditingController();
  // موجب = زيادة الرصيد، سالب = خصم.
  bool _increase = true;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  int get _signedAmount {
    final n = int.tryParse(_amount.text.trim()) ?? 0;
    return _increase ? n : -n;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    final result = await context.read<FinanceController>().addAdjustment(
          customerId: widget.customerId,
          amount: _signedAmount,
          reason: _reason.text.trim(),
          relatedPurchaseId: widget.relatedPurchaseId,
        );

    if (!mounted) return;
    setState(() => _busy = false);
    if (result.error != null) {
      setState(() => _error = result.error);
      return;
    }
    Navigator.of(context).pop(result.adjustment);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تصحيح مالي')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.customerName != null)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.person_outline),
                      title: Text(widget.customerName!),
                      subtitle: widget.relatedPurchaseId == null
                          ? const Text('تصحيح عام على الحساب')
                          : const Text('مرتبط بعملية محددة'),
                    ),
                  ),
                const SizedBox(height: 14),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: true,
                      label: Text('زيادة الرصيد'),
                      icon: Icon(Icons.add),
                    ),
                    ButtonSegment(
                      value: false,
                      label: Text('خصم من الرصيد'),
                      icon: Icon(Icons.remove),
                    ),
                  ],
                  selected: {_increase},
                  onSelectionChanged: (s) => setState(() => _increase = s.first),
                ),
                const SizedBox(height: 14),
                WizanoField(
                  label: _increase ? 'مبلغ الزيادة' : 'مبلغ الخصم',
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
                const SizedBox(height: 14),
                WizanoField(
                  label: 'السبب (إلزامي)',
                  controller: _reason,
                  textInputAction: TextInputAction.done,
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'سبب التصحيح مطلوب' : null,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 4),
                  Text(_error!, style: const TextStyle(color: WizanoColors.error)),
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
                      : const Text('تسجيل التصحيح'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

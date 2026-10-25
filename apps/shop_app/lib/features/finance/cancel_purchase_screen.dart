import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../app/widgets.dart';
import 'finance_controller.dart';

/// S22 — إلغاء عملية شراء عبر قيد عكسي موثَّق (سبب إلزامي).
///
/// يوضّح للمستخدم أن العملية الأصلية تبقى كما هي ويُنشأ قيد عكسي بقيمتها المتبقية.
class CancelPurchaseScreen extends StatefulWidget {
const CancelPurchaseScreen({
    super.key,
    required this.purchaseId,
    this.purchaseLabel,
    this.purchaseEffect,
    required this.purchaseVersion,
  });

  final String purchaseId;
  final String? purchaseLabel;
  final int? purchaseEffect;
  final int purchaseVersion;

  @override
  State<CancelPurchaseScreen> createState() => _CancelPurchaseScreenState();
}

class _CancelPurchaseScreenState extends State<CancelPurchaseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _reason = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    final result = await context.read<FinanceController>().cancelPurchase(
          purchaseId: widget.purchaseId,
          reason: _reason.text.trim(),
          version: widget.purchaseVersion,
        );

    if (!mounted) return;
    setState(() => _busy = false);
    if (result.error != null) {
      // إذا كان الخطأ بسبب تعارض (409)، نعرض إصدار الخادم ونطلب إعادة المحاولة.
      final error = result.error!;
      if (error.contains('CONFLICT') || error.contains('409') || error.contains('تعارض')) {
        setState(() {
          _error = 'تعارض: تم تعديل العملية من جهاز آخر. يرجى تحديث البيانات والمحاولة مرة أخرى.';
        });
        return;
      }
      setState(() => _error = result.error);
      return;
    }
    Navigator.of(context).pop(result.adjustment);
  }

  @override
  Widget build(BuildContext context) {
    final effect = widget.purchaseEffect;
    return Scaffold(
      appBar: AppBar(title: const Text('إلغاء العملية')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.info_outline, color: WizanoColors.navy),
                            SizedBox(width: 8),
                            Text(
                              'إلغاء بقيد عكسي',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: WizanoColors.textDark,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.purchaseLabel == null
                              ? 'تبقى العملية الأصلية في الكشف كما هي، '
                                  'ويُنشأ قيد عكسي بقيمتها المتبقية يصفّر أثرها على الرصيد.'
                              : 'العملية ${widget.purchaseLabel}: تبقى كما هي، '
                                  'ويُنشأ قيد عكسي بقيمتها المتبقية يصفّر أثرها على الرصيد.',
                          style: const TextStyle(color: WizanoColors.textMuted),
                        ),
                        if (effect != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            'إجمالي العملية: $effect — ويُعكس صافي أثرها '
                            '(الإجمالي ناقص المدفوعات والمرتجعات).',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: WizanoColors.error,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                WizanoField(
                  label: 'سبب الإلغاء (إلزامي)',
                  controller: _reason,
                  textInputAction: TextInputAction.done,
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'سبب الإلغاء مطلوب' : null,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 4),
                  Text(_error!, style: const TextStyle(color: WizanoColors.error)),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: _busy ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: WizanoColors.error,
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('تأكيد الإلغاء'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/widgets.dart';
import '../auth/auth_controller.dart';
import 'shop_controller.dart';

/// S04 — إعداد ملف المحل: الاسم، العملة (افتراضيًا YER)، المنطقة الزمنية، تاريخ الافتتاح.
class ShopSetupScreen extends StatefulWidget {
  const ShopSetupScreen({super.key});

  @override
  State<ShopSetupScreen> createState() => _ShopSetupScreenState();
}

class _ShopSetupScreenState extends State<ShopSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  String _currency = 'YER';
  String _timezone = 'Asia/Aden';
  DateTime? _openingDate;
  String? _error;

  static const _currencies = ['YER', 'SAR', 'USD', 'AED'];
  static const _timezones = ['Asia/Aden', 'Asia/Riyadh', 'Asia/Dubai', 'UTC'];

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _openingDate ?? now,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (picked != null) setState(() => _openingDate = picked);
  }

  String _formatDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _error = null);
    final shops = context.read<ShopController>();
    final auth = context.read<AuthController>();
    final error = await shops.create(
      name: _name.text.trim(),
      currency: _currency,
      timezone: _timezone,
      openingDate: _openingDate == null ? null : _formatDate(_openingDate!),
    );
    if (!mounted) return;
    if (error == null) {
      await auth.setActiveShopId(shops.active?.id);
    } else {
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = context.watch<ShopController>().loading;
    return Scaffold(
      appBar: AppBar(
        title: const Text('إعداد المحل'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'أدخل بيانات محلك للبدء',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 20),
                WizanoField(
                  label: 'اسم المحل',
                  controller: _name,
                  textInputAction: TextInputAction.done,
                  validator: (v) => (v == null || v.trim().length < 2)
                      ? 'أدخل اسم محل من حرفين على الأقل'
                      : null,
                ),
                DropdownButtonFormField<String>(
                  initialValue: _currency,
                  decoration: InputDecoration(
                    labelText: 'العملة',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  items: _currencies
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) => setState(() => _currency = v ?? 'YER'),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _timezone,
                  decoration: InputDecoration(
                    labelText: 'المنطقة الزمنية',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  items: _timezones
                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (v) => setState(() => _timezone = v ?? 'Asia/Aden'),
                ),
                const SizedBox(height: 14),
                InkWell(
                  onTap: _pickDate,
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'تاريخ الافتتاح (اختياري)',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      _openingDate == null ? 'غير محدد' : _formatDate(_openingDate!),
                      style: TextStyle(
                        color: _openingDate == null
                            ? const Color(0xFF6B7280)
                            : Colors.black87,
                      ),
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(color: Color(0xFFDC2626)),
                  ),
                ],
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: busy ? null : _submit,
                  child: busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('حفظ ومتابعة'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

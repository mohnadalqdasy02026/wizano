import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/widgets.dart';
import '../../domain/entities/models.dart';
import 'customer_controller.dart';

/// S10 — إضافة/تعديل عميل (بيانات غير مالية فقط).
class CustomerFormScreen extends StatefulWidget {
  const CustomerFormScreen({super.key, this.customer});

  final Customer? customer;

  bool get isEditing => customer != null;

  @override
  State<CustomerFormScreen> createState() => _CustomerFormScreenState();
}

class _CustomerFormScreenState extends State<CustomerFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _notes;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.customer?.displayName ?? '');
    _phone = TextEditingController(text: widget.customer?.phone ?? '');
    _notes = TextEditingController(text: widget.customer?.notes ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final controller = context.read<CustomerController>();
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    final notes = _notes.text.trim();

    final error = widget.isEditing
        ? await controller.edit(
            widget.customer!.id,
            displayName: name,
            phone: phone.isEmpty ? null : phone,
            notes: notes.isEmpty ? null : notes,
          )
        : await controller.add(
            displayName: name,
            phone: phone.isEmpty ? null : phone,
            notes: notes.isEmpty ? null : notes,
          );

    if (!mounted) return;
    setState(() => _busy = false);
    if (error == null) {
      Navigator.of(context).pop();
    } else {
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'تعديل عميل' : 'عميل جديد'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                WizanoField(
                  label: 'الاسم',
                  controller: _name,
                  textInputAction: TextInputAction.next,
                  validator: (v) => (v == null || v.trim().length < 2)
                      ? 'أدخل اسمًا من حرفين على الأقل'
                      : null,
                ),
                WizanoField(
                  label: 'الهاتف (اختياري)',
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                ),
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
                      : Text(widget.isEditing ? 'حفظ التعديلات' : 'إضافة العميل'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

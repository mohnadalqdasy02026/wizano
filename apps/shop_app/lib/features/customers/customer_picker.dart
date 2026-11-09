import 'package:flutter/material.dart';

import '../../domain/entities/models.dart';

/// حقل اختيار عميل قابل للبحث.
///
/// القائمة المنسدلة العادية غير عملية مع آلاف العملاء، لذلك نفتح ورقة سفلية
/// فيها مربع بحث فوري بالاسم أو الهاتف. التصفية محلية على القائمة المحمّلة،
/// وتتجاهل فروق الهمزات والتشكيل حتى يجد المستخدم ما يريده بسرعة.
class CustomerPickerField extends StatelessWidget {
  const CustomerPickerField({
    super.key,
    required this.customers,
    required this.onChanged,
    this.initialValue,
    this.label = 'العميل',
    this.validator,
  });

  final List<Customer> customers;
  final ValueChanged<String?> onChanged;
  final String? initialValue;
  final String label;
  final String? Function(String?)? validator;

  Future<void> _pick(BuildContext context, FormFieldState<String> field) async {
    final selected = await showModalBottomSheet<Customer>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _CustomerSearchSheet(
        customers: customers,
        selectedId: field.value,
      ),
    );
    if (selected == null) return;
    field.didChange(selected.id);
    onChanged(selected.id);
  }

  @override
  Widget build(BuildContext context) {
    return FormField<String>(
      initialValue: initialValue,
      validator: validator,
      builder: (field) {
        Customer? selected;
        for (final customer in customers) {
          if (customer.id == field.value) {
            selected = customer;
            break;
          }
        }
        return InkWell(
          onTap: () => _pick(context, field),
          borderRadius: BorderRadius.circular(12),
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: label,
              errorText: field.errorText,
              filled: true,
              fillColor: Colors.white,
              suffixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
            ),
            child: Text(
              selected?.displayName ?? 'ابحث واختر العميل',
              style: TextStyle(
                color: selected == null
                    ? Theme.of(context).hintColor
                    : Theme.of(context).textTheme.bodyLarge?.color,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CustomerSearchSheet extends StatefulWidget {
  const _CustomerSearchSheet({
    required this.customers,
    this.selectedId,
  });

  final List<Customer> customers;
  final String? selectedId;

  @override
  State<_CustomerSearchSheet> createState() => _CustomerSearchSheetState();
}

class _CustomerSearchSheetState extends State<_CustomerSearchSheet> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  static String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[أإآٱ]'), 'ا')
      .replaceAll('ى', 'ي')
      .replaceAll('ة', 'ه')
      .replaceAll(RegExp(r'[\u064B-\u0652\u0670\u0640]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  List<Customer> get _filtered {
    final query = _normalize(_search.text);
    if (query.isEmpty) return widget.customers;
    final digits = query.replaceAll(RegExp(r'[^0-9]'), '');
    return widget.customers.where((customer) {
      if (_normalize(customer.displayName).contains(query)) return true;
      final phone = _normalize(customer.phone ?? '');
      if (phone.contains(query)) return true;
      if (digits.isNotEmpty && phone.replaceAll(RegExp(r'[^0-9]'), '').contains(digits)) {
        return true;
      }
      return false;
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final results = _filtered;
    final height = MediaQuery.of(context).size.height * 0.82;
    return SizedBox(
      height: height,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _search,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'ابحث بالاسم أو الهاتف...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _search.clear();
                          setState(() {});
                        },
                      ),
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  '${results.length} عميل',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: results.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        widget.customers.isEmpty
                            ? 'جارٍ تحميل العملاء...'
                            : 'لا نتائج مطابقة للبحث.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).hintColor,
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: results.length,
                    itemBuilder: (context, index) {
                      final customer = results[index];
                      final selected = customer.id == widget.selectedId;
                      return ListTile(
                        leading: CircleAvatar(
                          child: Text(
                            customer.displayName.characters.first,
                          ),
                        ),
                        title: Text(customer.displayName),
                        subtitle: customer.phone == null
                            ? null
                            : Text(customer.phone!),
                        trailing: selected
                            ? const Icon(Icons.check, color: Colors.teal)
                            : null,
                        onTap: () => Navigator.of(context).pop(customer),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

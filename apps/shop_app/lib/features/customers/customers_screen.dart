import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../domain/entities/models.dart';
import 'customer_controller.dart';
import 'customer_form_screen.dart';
import 'customer_profile_screen.dart';

/// S09 — قائمة العملاء + بحث.
class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) context.read<CustomerController>().load(search: value);
    });
  }

  Future<void> _openAdd() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CustomerFormScreen()),
    );
  }

  Future<void> _openProfile(Customer customer) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CustomerProfileScreen(customerId: customer.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<CustomerController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('العملاء'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'بحث بالاسم أو الهاتف...',
                hintStyle: const TextStyle(color: Colors.white70),
                prefixIcon: const Icon(Icons.search, color: Colors.white70),
                filled: true,
                fillColor: Colors.white24,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAdd,
        icon: const Icon(Icons.person_add_alt),
        label: const Text('عميل جديد'),
      ),
      body: _buildBody(controller),
    );
  }

  Widget _buildBody(CustomerController controller) {
    if (controller.loading && controller.customers.isEmpty) {
      return const LoadingState(message: 'جارٍ تحميل العملاء...');
    }
    if (controller.error != null && controller.customers.isEmpty) {
      return ErrorState(
        message: controller.error!,
        onRetry: () => controller.load(search: _searchController.text),
      );
    }
    if (controller.customers.isEmpty) {
      final searching = _searchController.text.trim().isNotEmpty;
      // السحب للتحديث متاح حتى في حالة الفراغ (تحديث القائمة/الطابور).
      return RefreshIndicator(
        onRefresh: () => controller.load(search: _searchController.text),
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: EmptyState(
                message: searching
                    ? 'لا نتائج مطابقة للبحث.'
                    : 'لا عملاء بعد — أضف عميلك الأول.',
                icon: Icons.people_outline,
                actionLabel: searching ? null : 'إضافة عميل',
                onAction: searching ? null : _openAdd,
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        if (controller.offline)
          Container(
            width: double.infinity,
            color: WizanoColors.gold.withValues(alpha: 0.16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: const Text(
              'نسخة محفوظة على الجهاز — لا يوجد اتصال بالخادم.',
              style: TextStyle(
                color: WizanoColors.navy,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => controller.load(search: _searchController.text),
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 88),
              itemCount: controller.customers.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final c = controller.customers[i];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: WizanoColors.navy,
                    child: Text(
                      c.displayName.characters.first,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  title: Text(c.displayName),
                  subtitle: c.phone == null ? null : Text(c.phone!),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: () => _openProfile(c),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

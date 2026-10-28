import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../domain/entities/models.dart';
import '../customers/customer_controller.dart';
import '../shop/shop_controller.dart';
import 'customer_messages_screen.dart';

/// تبويب مستقل للمحادثات: يتيح لصاحب المحل الوصول السريع إلى أي عميل.
class MessagesScreen extends StatelessWidget {
  const MessagesScreen({super.key});

  void _openConversation(BuildContext context, Customer customer) {
    final shopId = context.read<ShopController>().active?.id;
    if (shopId == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CustomerMessagesScreen(
          shopId: shopId,
          customerId: customer.id,
          customerName: customer.displayName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final customers = context.watch<CustomerController>();
    return Scaffold(
      appBar: AppBar(title: const Text('الرسائل')),
      body: customers.loading && customers.customers.isEmpty
          ? const LoadingState(message: 'جارٍ تحميل المحادثات...')
          : customers.customers.isEmpty
              ? (customers.offline
                  ? OfflineEmptyState(onRetry: customers.load)
                  : const EmptyState(
                      icon: Icons.forum_outlined,
                      message:
                          'لا توجد محادثات بعد. أضف عميلًا أو افتح محادثته.',
                    ))
              : Column(
                  children: [
                    if (customers.offline)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 9,
                        ),
                        color: WizanoColors.gold.withValues(alpha: .20),
                        child: const Text(
                          'غير متصل — اختر من المحادثات المحفوظة على الجهاز.',
                          style: TextStyle(
                            color: WizanoColors.navy,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 92),
                        itemCount: customers.customers.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 7),
                        itemBuilder: (context, index) {
                          final customer = customers.customers[index];
                          return TweenAnimationBuilder<double>(
                            key: ValueKey(customer.id),
                            duration: const Duration(milliseconds: 240),
                            tween: Tween(begin: 0, end: 1),
                            builder: (_, value, child) => Opacity(
                              opacity: value,
                              child: Transform.translate(
                                offset: Offset(0, 10 * (1 - value)),
                                child: child,
                              ),
                            ),
                            child: Card(
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: WizanoColors.navy,
                                  child: Text(
                                    customer.displayName.characters.first,
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ),
                                title: Text(
                                  customer.displayName,
                                  style: const TextStyle(fontWeight: FontWeight.w800),
                                ),
                                subtitle: Text(
                                  customer.phone ?? 'اضغط لفتح المحادثة',
                                ),
                                trailing: const Icon(Icons.forum_rounded),
                                onTap: () => _openConversation(context, customer),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}

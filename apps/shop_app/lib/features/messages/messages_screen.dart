import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../data/remote/api_client.dart';
import '../../domain/entities/models.dart';
import '../shop/shop_controller.dart';
import 'customer_messages_screen.dart';

/// قائمة محادثات شبيهة بواتساب: آخر رسالة وعدد الوارد غير المقروء.
class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  List<ConversationSummary> _items = const [];
  Timer? _poller;
  bool _loading = true;
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    _poller = Timer.periodic(const Duration(seconds: 8), (_) => _load());
  }

  @override
  void dispose() {
    _poller?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final shopId = context.read<ShopController>().active?.id;
    if (shopId == null) return;
    try {
      final items = await context.read<ApiClient>().listMessageSummaries(shopId);
      if (!mounted) return;
      setState(() { _items = items; _loading = false; _offline = false; });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _offline = true; });
    }
  }

  Future<void> _open(ConversationSummary item) async {
    final shopId = context.read<ShopController>().active?.id;
    if (shopId == null) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CustomerMessagesScreen(
        shopId: shopId,
        customerId: item.customerId,
        customerName: item.customerName,
      ),
    ));
    _load();
  }

  String _time(String value) {
    try {
      return DateFormat('hh:mm a', 'ar').format(DateTime.parse(value).toLocal());
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('الرسائل'),
      actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded), tooltip: 'تحديث')],
    ),
    body: _loading
        ? const LoadingState(message: 'جارٍ تحميل المحادثات...')
        : _items.isEmpty
            ? (_offline
                ? OfflineEmptyState(onRetry: _load)
                : const EmptyState(icon: Icons.forum_outlined, message: 'لا توجد رسائل بعد.'))
            : Column(children: [
                if (_offline)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('تعذر تحديث الرسائل الآن. تظهر آخر بيانات محفوظة.', style: TextStyle(color: WizanoColors.textMuted)),
                  ),
                Expanded(child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 92),
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 7),
                  itemBuilder: (_, index) {
                    final item = _items[index];
                    final preview = item.lastIsAudio ? '🎤 رسالة صوتية' : (item.lastBody ?? 'رسالة جديدة');
                    return Card(child: ListTile(
                      onTap: () => _open(item),
                      leading: CircleAvatar(backgroundColor: WizanoColors.navy, child: Text(item.customerName.characters.first, style: const TextStyle(color: Colors.white))),
                      title: Text(item.customerName, style: TextStyle(fontWeight: item.unreadCount > 0 ? FontWeight.w900 : FontWeight.w700)),
                      subtitle: Text(preview, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: item.unreadCount > 0 ? FontWeight.w700 : FontWeight.w400)),
                      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text(_time(item.lastCreatedAt), style: const TextStyle(fontSize: 10, color: WizanoColors.textMuted)),
                        const SizedBox(height: 5),
                        if (item.unreadCount > 0) Container(
                          constraints: const BoxConstraints(minWidth: 21),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: const BoxDecoration(color: WizanoColors.teal, shape: BoxShape.circle),
                          child: Text('${item.unreadCount}', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11)),
                        ),
                      ]),
                    ));
                  },
                )),
              ]),
  );
}

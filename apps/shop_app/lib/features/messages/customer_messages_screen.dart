import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../data/remote/api_client.dart';
import '../../domain/entities/models.dart';

/// محادثة خاصة بين صاحب المحل والعميل المحدد.
class CustomerMessagesScreen extends StatefulWidget {
  const CustomerMessagesScreen({
    super.key,
    required this.shopId,
    required this.customerId,
    required this.customerName,
  });

  final String shopId;
  final String customerId;
  final String customerName;

  @override
  State<CustomerMessagesScreen> createState() => _CustomerMessagesScreenState();
}

class _CustomerMessagesScreenState extends State<CustomerMessagesScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  List<ConversationMessage> _messages = const [];
  String? _error;
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final messages = await context.read<ApiClient>().listCustomerMessages(
            widget.shopId,
            widget.customerId,
          );
      if (!mounted) return;
      setState(() {
        _messages = messages;
        _error = null;
        _loading = false;
      });
      _scrollToLatest();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'تعذر تحميل المحادثة. تحقق من اتصال الإنترنت ثم أعد المحاولة.';
        _loading = false;
      });
    }
  }

  Future<void> _send() async {
    final body = _textController.text.trim();
    if (body.isEmpty || _sending) return;

    setState(() => _sending = true);
    try {
      final message = await context.read<ApiClient>().sendCustomerMessage(
            widget.shopId,
            widget.customerId,
            body,
          );
      if (!mounted) return;
      _textController.clear();
      setState(() {
        _messages = [..._messages, message];
        _sending = false;
      });
      _scrollToLatest();
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر إرسال الرسالة. حاول مرة أخرى.')),
      );
    }
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  String _time(String value) {
    try {
      return DateFormat('hh:mm a', 'ar').format(DateTime.parse(value).toLocal());
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('مراسلة العميل'),
            Text(
              widget.customerName,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildMessages()),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 2000,
                      textInputAction: TextInputAction.newline,
                      decoration: const InputDecoration(
                        hintText: 'اكتب رسالة للعميل…',
                        counterText: '',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'إرسال',
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessages() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }
    if (_messages.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forum_outlined, size: 48, color: WizanoColors.textMuted),
            SizedBox(height: 10),
            Text('ابدأ المحادثة مع العميل برسالة واضحة.'),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        itemCount: _messages.length,
        itemBuilder: (context, index) {
          final message = _messages[index];
          final mine = message.isFromShop;
          return Align(
            alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 310),
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 7),
              decoration: BoxDecoration(
                color: mine ? WizanoColors.navy : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: mine ? null : Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Column(
                crossAxisAlignment:
                    mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  Text(
                    message.body,
                    style: TextStyle(color: mine ? Colors.white : WizanoColors.textDark),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _time(message.createdAt),
                    style: TextStyle(
                      fontSize: 10,
                      color: mine ? Colors.white70 : WizanoColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

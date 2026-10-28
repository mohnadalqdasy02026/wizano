import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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
  final _cache = const FlutterSecureStorage();
  List<ConversationMessage> _messages = const [];
  String? _error;
  Timer? _poller;
  bool _offline = false;
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _restoreCache();
    _load();
    _poller = Timer.periodic(const Duration(seconds: 7), (_) => _load());
  }

  @override
  void dispose() {
    _poller?.cancel();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String get _cacheKey =>
      'wizano.shop.messages.${widget.shopId}.${widget.customerId}';

  Future<void> _restoreCache() async {
    final raw = await _cache.read(key: _cacheKey);
    if (raw == null) return;
    try {
      final rows = jsonDecode(raw) as List<dynamic>;
      final messages = rows
          .map((row) => ConversationMessage.fromJson(
                row as Map<String, dynamic>,
              ))
          .toList(growable: false);
      if (mounted) setState(() { _messages = messages; _loading = false; });
    } catch (_) {
      // نسخة قديمة أو غير صالحة: نتجاهلها ونأخذ النسخة القادمة من الخادم.
    }
  }

  Future<void> _cacheMessages(List<ConversationMessage> messages) => _cache.write(
        key: _cacheKey,
        value: jsonEncode([
          for (final message in messages)
            {
              'id': message.id,
              'body': message.body,
              'senderType': message.senderType,
              'createdAt': message.createdAt,
              'readAt': message.readAt,
              'pending': message.pending,
            },
        ]),
      );

  Future<void> _load() async {
    try {
      await _flushPending();
      final messages = await context.read<ApiClient>().listCustomerMessages(
            widget.shopId,
            widget.customerId,
          );
      if (!mounted) return;
      final pending = _messages.where((message) => message.pending).toList();
      final merged = [...messages, ...pending];
      final receivedNew = merged.length > _messages.length;
      await _cacheMessages(merged);
      setState(() {
        _messages = merged;
        _error = null;
        _loading = false;
        _offline = false;
      });
      if (receivedNew) _scrollToLatest();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = _messages.isEmpty
            ? 'لا توجد رسائل محفوظة بعد. سيتصل التطبيق تلقائيًا عند عودة الإنترنت.'
            : null;
        _loading = false;
        _offline = true;
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
        _offline = false;
      });
      await _cacheMessages(_messages);
      _scrollToLatest();
    } catch (_) {
      if (!mounted) return;
      final local = ConversationMessage(
        id: 'local-${DateTime.now().microsecondsSinceEpoch}',
        body: body,
        senderType: 'shop',
        createdAt: DateTime.now().toUtc().toIso8601String(),
        pending: true,
      );
      _textController.clear();
      setState(() {
        _messages = [..._messages, local];
        _sending = false;
        _offline = true;
      });
      await _cacheMessages(_messages);
      _scrollToLatest();
    }
  }

  Future<void> _flushPending() async {
    final pending = _messages.where((message) => message.pending).toList();
    if (pending.isEmpty) return;
    var updated = List<ConversationMessage>.from(_messages);
    for (final message in pending) {
      try {
        final sent = await context.read<ApiClient>().sendCustomerMessage(
              widget.shopId,
              widget.customerId,
              message.body,
            );
        updated = [for (final current in updated) if (current.id == message.id) sent else current];
      } catch (_) {
        break;
      }
    }
    if (mounted) setState(() => _messages = updated);
    await _cacheMessages(updated);
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
      ),
      body: Column(
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            child: _offline
                ? Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    color: WizanoColors.navyBright,
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.cloud_off_rounded, size: 16, color: Colors.white),
                        SizedBox(width: 6),
                        Text('غير متصل — تعرض آخر محادثة محفوظة', style: TextStyle(color: Colors.white, fontSize: 12)),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
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
    return ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        itemCount: _messages.length,
        itemBuilder: (context, index) {
          final message = _messages[index];
          // في واجهة صاحب المحل: رسائله يسار ورسائل العميل يمين.
          final mine = message.isFromShop;
          return TweenAnimationBuilder<double>(
            key: ValueKey(message.id),
            duration: const Duration(milliseconds: 280),
            tween: Tween(begin: 0, end: 1),
            builder: (_, value, child) => Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset(0, 14 * (1 - value)),
                child: child,
              ),
            ),
            child: Align(
              alignment: mine ? Alignment.centerLeft : Alignment.centerRight,
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
                    mine ? CrossAxisAlignment.start : CrossAxisAlignment.end,
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
                  if (message.pending)
                    const Padding(
                      padding: EdgeInsets.only(top: 3),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.error_outline_rounded, color: WizanoColors.error, size: 14),
                          SizedBox(width: 4),
                          Text('لم تُرسل', style: TextStyle(fontSize: 10, color: WizanoColors.error, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                ],
              ),
              ),
            ),
          );
        },
    );
  }
}

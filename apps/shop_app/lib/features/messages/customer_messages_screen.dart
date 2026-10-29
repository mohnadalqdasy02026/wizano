import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

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
  final _recorder = AudioRecorder();
  final _player = AudioPlayer();
  List<ConversationMessage> _messages = const [];
  String? _error;
  Timer? _poller;
  Timer? _recordingTimer;
  bool _offline = false;
  bool _loading = true;
  bool _sending = false;
  bool _recording = false;
  int _recordingSeconds = 0;
  bool _initialPositioned = false;

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
    _recordingTimer?.cancel();
    _recorder.dispose();
    _player.dispose();
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
      if (mounted) {
        setState(() { _messages = messages; _loading = false; });
        _scrollToLatest(immediate: true);
      }
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
              'audioBase64': message.audioBase64,
              'audioMimeType': message.audioMimeType,
              'audioDurationMs': message.audioDurationMs,
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
      if (!_initialPositioned || receivedNew) _scrollToLatest(immediate: !_initialPositioned);
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
            body: body,
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
              body: message.body,
              audioBase64: message.audioBase64,
              audioMimeType: message.audioMimeType,
              audioDurationMs: message.audioDurationMs,
            );
        updated = [for (final current in updated) if (current.id == message.id) sent else current];
      } catch (_) {
        break;
      }
    }
    if (mounted) setState(() => _messages = updated);
    await _cacheMessages(updated);
  }

  Future<void> _recordVoice() async {
    if (_recording) {
      _recordingTimer?.cancel();
      final path = await _recorder.stop();
      if (!mounted) return;
      setState(() => _recording = false);
      if (path == null || _recordingSeconds < 1) return;
      final bytes = await File(path).readAsBytes();
      if (bytes.length > 1000000) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الرسالة الصوتية طويلة جدًا؛ الحد الأقصى 30 ثانية.')));
        return;
      }
      await _sendVoice(base64Encode(bytes), _recordingSeconds * 1000);
      return;
    }
    if (!await _recorder.hasPermission()) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اسمح للتطبيق باستخدام الميكروفون أولًا.')));
      return;
    }
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/wizano_voice_${DateTime.now().microsecondsSinceEpoch}.m4a';
    await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 32000, sampleRate: 16000), path: path);
    if (!mounted) return;
    setState(() { _recording = true; _recordingSeconds = 0; });
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_recordingSeconds >= 30) { _recordVoice(); return; }
      setState(() => _recordingSeconds++);
    });
  }

  Future<void> _sendVoice(String audioBase64, int durationMs) async {
    try {
      final message = await context.read<ApiClient>().sendCustomerMessage(
        widget.shopId, widget.customerId,
        audioBase64: audioBase64, audioMimeType: 'audio/mp4', audioDurationMs: durationMs,
      );
      if (!mounted) return;
      setState(() { _messages = [..._messages, message]; _offline = false; });
      await _cacheMessages(_messages);
      _scrollToLatest();
    } catch (_) {
      if (!mounted) return;
      final local = ConversationMessage(
        id: 'local-${DateTime.now().microsecondsSinceEpoch}', senderType: 'shop',
        createdAt: DateTime.now().toUtc().toIso8601String(), audioBase64: audioBase64,
        audioMimeType: 'audio/mp4', audioDurationMs: durationMs, pending: true,
      );
      setState(() { _messages = [..._messages, local]; _offline = true; });
      await _cacheMessages(_messages);
      _scrollToLatest();
    }
  }

  Future<void> _playVoice(ConversationMessage message) async {
    final encoded = message.audioBase64;
    if (encoded == null || encoded.isEmpty) return;
    await _player.setAudioSource(AudioSource.uri(Uri.dataFromBytes(
      base64Decode(encoded), mimeType: message.audioMimeType ?? 'audio/mp4',
    )));
    await _player.play();
  }

  void _scrollToLatest({bool immediate = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _initialPositioned = true;
      if (immediate) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      } else {
        _scrollController.animateTo(_scrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
      }
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
                  IconButton(
                    tooltip: _recording ? 'إيقاف وإرسال الصوت' : 'رسالة صوتية',
                    onPressed: _sending ? null : _recordVoice,
                    icon: Icon(
                      _recording ? Icons.stop_circle_rounded : Icons.mic_rounded,
                      color: _recording ? WizanoColors.error : WizanoColors.navy,
                    ),
                  ),
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
                  if (message.audioBase64?.isNotEmpty == true)
                    InkWell(
                      onTap: () => _playVoice(message),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.play_circle_fill_rounded, color: mine ? Colors.white : WizanoColors.navy),
                          const SizedBox(width: 7),
                          Text(
                            'رسالة صوتية ${((message.audioDurationMs ?? 0) ~/ 1000)} ث',
                            style: TextStyle(color: mine ? Colors.white : WizanoColors.navy, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    )
                  else
                    Text(
                      message.body ?? '',
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

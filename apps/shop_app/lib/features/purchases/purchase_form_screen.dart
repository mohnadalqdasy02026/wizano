import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../core/connectivity.dart';
import '../../features/customers/customer_controller.dart';
import '../speech/speech_controller.dart';
import '../speech/voice_model_screen.dart';
import 'purchase_controller.dart';
import 'purchase_details_screen.dart';

/// S13 — تسجيل مشتريات آجلة (عميل، تفاصيل نصية، إجمالي، مدفوع، متبقي تلقائي).
class PurchaseFormScreen extends StatefulWidget {
  const PurchaseFormScreen({super.key});

  @override
  State<PurchaseFormScreen> createState() => _PurchaseFormScreenState();
}

class _PurchaseFormScreenState extends State<PurchaseFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _items = TextEditingController();
  final _total = TextEditingController();
  final _paid = TextEditingController(text: '0');
  final _notes = TextEditingController();
  String? _customerId;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _total.addListener(_recompute);
    _paid.addListener(_recompute);
  }

  @override
  void dispose() {
    _total.dispose();
    _paid.dispose();
    _items.dispose();
    _notes.dispose();
    super.dispose();
  }

  int get _totalValue => int.tryParse(_total.text.trim()) ?? 0;
  int get _paidValue => int.tryParse(_paid.text.trim()) ?? 0;
  int get _remaining => _totalValue - _paidValue;

  void _recompute() => setState(() {});

  void _showSpeechError(SpeechController speech) {
    final message = speech.error;
    if (!mounted || message == null || message.isEmpty) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(message),
          duration: const Duration(seconds: 4),
        ),
      );
    speech.clear();
  }

  /// مسار اختبار E2E: مسار ملف صوتي محلي يُفكّ ترميزه مباشرةً.
  /// مُفعَّل فقط عند البناء مع dart-define باسم WIZANO_STT_TEST_WAV،
  /// فلا وجود له في البناءات العادية.
  static const String _sttTestWav = String.fromEnvironment('WIZANO_STT_TEST_WAV');

  /// مزامنة «قاموس المحل»: أصناف العمليات السابقة تصبح مفردات توجيه
  /// للمحرّك (hotwords)، فيتحسّن التعرّف على أصناف هذا المحل بعينه — بلا إنترنت.
  Future<void> _syncVocabulary(SpeechController speech) async {
    final purchases = context.read<PurchaseController>().purchases;
    if (purchases.isEmpty) return;
    await speech.setShopTerms(purchases.map((p) => p.itemsText));
  }

  Future<void> _onMicPressed() async {
    final speech = context.read<SpeechController>();
    await _syncVocabulary(speech);

    if (_sttTestWav.isNotEmpty) {
      await speech.transcribePath(_sttTestWav);
      final text = speech.text;
      if (text.isNotEmpty) {
        _items.text = _items.text.trim().isEmpty
            ? text
            : '${_items.text.trim()}\n$text';
      }
      _showSpeechError(speech);
      setState(() {});
      return;
    }

    if (speech.state == SpeechState.recording) {
      await speech.stopAndTranscribe();
      final text = speech.text;
      if (text.isNotEmpty) {
        _items.text = _items.text.trim().isEmpty
            ? text
            : '${_items.text.trim()}\n$text';
      }
      _showSpeechError(speech);
      setState(() {});
      return;
    }

    if (!speech.modelManager.info.isReady) {
      // قد يكون الفحص الأول لم يكتمل بعد (فحص القرص غير متزامن).
      await speech.ensureModel();
      if (!mounted) return;
    }
    if (!speech.modelManager.info.isReady) {
      if (!mounted) return;
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('نموذج التعرف غير محمّل'),
          content: const Text(
            'لتحويل الصوت إلى نص على جهازك، نزّل نموذج التعرف أولًا (مرة واحدة فقط). بعدها يعمل الإدخال الصوتي دون إنترنت.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('لاحقًا'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('تنزيل النموذج'),
            ),
          ],
        ),
      );
      if (go == true) {
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const VoiceModelScreen()),
        );
      }
      return;
    }

    await speech.startRecording();
    _showSpeechError(speech);
    setState(() {});
  }

  Widget _micButton(BuildContext context) {
    final speech = context.watch<SpeechController>();
    final recording = speech.state == SpeechState.recording;
    final processing = speech.state == SpeechState.processing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: processing ? null : () => _onMicPressed(),
          icon: Icon(recording ? Icons.stop_circle : Icons.mic, size: 22),
          label: Text(
            recording
                ? 'إيقاف التسجيل'
                : processing
                    ? 'جارٍ التعرّف...'
                    : 'إدخال التفاصيل بالصوت',
          ),
        ),
        if (recording)
          Container(
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: WizanoColors.navy.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: WizanoColors.navy.withValues(alpha: 0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.graphic_eq, size: 18, color: WizanoColors.navy),
                    const SizedBox(width: 8),
                    Text(
                      speech.partial.isEmpty
                          ? 'جارٍ الاستماع... تحدّث الآن'
                          : 'جارٍ الاستماع...',
                      style: const TextStyle(
                        color: WizanoColors.navy,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                if (speech.partial.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    speech.partial,
                    style: const TextStyle(fontSize: 16, height: 1.6),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_customerId == null) {
      setState(() => _error = 'اختر العميل أولًا.');
      return;
    }
    if (_paidValue > _totalValue) {
      setState(() => _error = 'المبلغ المدفوع لا يتجاوز الإجمالي.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final result = await context.read<PurchaseController>().add(
          customerId: _customerId!,
          itemsText: _items.text.trim(),
          totalAmount: _totalValue,
          paidAmount: _paidValue,
          notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        );

    if (!mounted) return;
    setState(() => _busy = false);
    if (result.error != null) {
      setState(() => _error = result.error);
      return;
    }

    if (result.savedLocally) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تعذّر الوصول إلى الخادم — حُفظت العملية محليًا وستُرسل عند توفّر الاتصال.',
          ),
        ),
      );
    }

    // الانتقال إلى S15 (تفاصيل العملية).
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => PurchaseDetailsScreen(purchase: result.purchase!),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final customers = context.watch<CustomerController>().customers;
    final offline = context.watch<ConnectivityMonitor>().offline;

    return Scaffold(
      appBar: AppBar(title: const Text('تسجيل مشتريات')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (offline) ...[
                  const OfflineNotice(),
                  const SizedBox(height: 14),
                ],
                DropdownButtonFormField<String>(
                  initialValue: _customerId,
                  decoration: const InputDecoration(
                    labelText: 'العميل',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
                  ),
                  items: customers
                      .map(
                        (c) => DropdownMenuItem(
                          value: c.id,
                          child: Text(c.displayName),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _customerId = v),
                  validator: (v) => v == null ? 'اختر العميل' : null,
                ),
                const SizedBox(height: 14),
                _micButton(context),
                const SizedBox(height: 14),
                WizanoField(
                  label: 'تفاصيل الأصناف (نصًا)',
                  controller: _items,
                  textInputAction: TextInputAction.next,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'أدخل تفاصيل الأصناف' : null,
                ),
                WizanoField(
                  label: 'الإجمالي',
                  controller: _total,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  validator: (v) {
                    final n = int.tryParse((v ?? '').trim());
                    if (n == null) return 'أدخل رقمًا صحيحًا';
                    if (n < 0) return 'الإجمالي لا يكون سالبًا';
                    return null;
                  },
                ),
                WizanoField(
                  label: 'المبلغ المدفوع',
                  controller: _paid,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  validator: (v) {
                    final n = int.tryParse((v ?? '').trim());
                    if (n == null) return 'أدخل رقمًا صحيحًا';
                    if (n < 0) return 'المدفوع لا يكون سالبًا';
                    return null;
                  },
                ),
                Card(
                  color: WizanoColors.navy.withValues(alpha: 0.06),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'المتبقي',
                          style: TextStyle(color: WizanoColors.textMuted),
                        ),
                        Text(
                          '$_remaining',
                          style: const TextStyle(
                            color: WizanoColors.navy,
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
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
                      : const Text('تسجيل العملية'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}





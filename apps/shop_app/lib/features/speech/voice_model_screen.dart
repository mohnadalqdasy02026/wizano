import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import 'speech_engine.dart';
import 'speech_controller.dart';

/// شاشة تنزيل نموذج التعرف على الكلام المحلي (S14).
/// النموذج يُنزَّل مرة واحدة، ثم يعمل التطبيق دون اتصال تمامًا.
class VoiceModelScreen extends StatefulWidget {
  const VoiceModelScreen({super.key});

  @override
  State<VoiceModelScreen> createState() => _VoiceModelScreenState();
}

class _VoiceModelScreenState extends State<VoiceModelScreen> {
  StreamSubscription<ModelInfo>? _sub;

  @override
  void initState() {
    super.initState();
    final manager = context.read<SpeechController>().modelManager;
    _sub = manager.infoStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SpeechController>();
    final info = controller.modelManager.info;

    return Scaffold(
      appBar: AppBar(title: const Text('نموذج التعرف على الصوت')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                color: WizanoColors.navy.withValues(alpha: 0.06),
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'وضع دون اتصال: نموذج محلي احتياطي',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: WizanoColors.navy,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'عند الاتصال يستخدم زر الصوت خدمة الهاتف عالية الدقة لأسماء المنتجات العربية. عند انقطاع الإنترنت، يستخدم وزانو نموذج Whisper المحلي الأقوى كبديل؛ راجع النص دائمًا قبل الحفظ.',
                        style: TextStyle(color: WizanoColors.textMuted),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _statusRow(info),
              if (info.status == ModelStatus.downloading) ...[
                const SizedBox(height: 16),
                LinearProgressIndicator(value: info.progress),
                const SizedBox(height: 8),
                Text(
                  '${(info.bytesDownloaded / 1048576).toStringAsFixed(1)} من ${(info.bytesTotal / 1048576).toStringAsFixed(1)} ميجابايت',
                  style: const TextStyle(color: WizanoColors.textMuted),
                ),
              ],
              const SizedBox(height: 24),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.record_voice_over_outlined),
                title: Text('النص المنطوق كما تعرّف عليه المحرك'),
                subtitle: Text('لا يبدّل وزانو الكلمات أو يصححها تلقائيًا؛ راجع النص قبل الحفظ عند الحاجة.'),
              ),
              const SizedBox(height: 12),
              if (info.status == ModelStatus.ready)
                ElevatedButton(
                  onPressed: () => controller.modelManager.deleteModel(),
                  child: const Text('حذف النموذج'),
                )
              else
                ElevatedButton(
                  onPressed: info.status == ModelStatus.downloading
                      ? null
                      : () => controller.ensureModel(),
                  child: Text(
                    info.status == ModelStatus.downloading
                        ? 'جارٍ التنزيل...'
                        : 'تنزيل نموذج Whisper المحلي (~165 ميجابايت)',
                  ),
                ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('رجوع'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusRow(ModelInfo info) {
    final (String label, IconData icon, Color color) = switch (info.status) {
      ModelStatus.notDownloaded => ('لم يُنزَّل بعد', Icons.download_outlined, WizanoColors.textMuted),
      ModelStatus.downloading => ('جارٍ التنزيل...', Icons.downloading, WizanoColors.gold),
      ModelStatus.verifying => ('جارٍ التحقق من الملف', Icons.check_circle_outline, WizanoColors.gold),
      ModelStatus.ready => ('جاهز — يعمل دون اتصال', Icons.check_circle, Colors.green),
      ModelStatus.error => ('حدث خطأ أثناء التنزيل', Icons.error_outline, Colors.red),
    };

    return Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}


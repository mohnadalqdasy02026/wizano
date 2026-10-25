import 'dart:async';
import 'dart:typed_data';

import '../../services/speech/wav_reader.dart';

/// واجهة محرك التعرف على الكلام محليًا (قابلة للاستبدال).
/// لا يتم إرسال الصوت إلى أي خدمة خارجية.
abstract class SpeechEngine {
  Future<void> init({required String modelDir});
  Future<bool> isReady();

  /// يفكّ ترميز ملف WAV كاملًا إلى نص.
  Future<String> transcribeFile(String wavPath);

  /// يفكّ ترميز عيّنات صوتية مباشرةً (تُستخدم للعرض الحيّ أثناء التسجيل).
  Future<String> transcribeSamples(Float32List samples, int sampleRate);

  /// يحدّث ملف مفردات التمييز (hotwords) الذي يميل إليه المحرّك.
  Future<void> setHotwords(String? hotwordsFile);

  Future<void> dispose();
  String get engineName;
}

/// مزوّد النموذج المحلي (تحميل/حذف/تقدم).
abstract class ModelProvider {
  ModelInfo get info;
  Stream<ModelInfo> get infoStream;
  Future<void> ensureReady({bool force = false});
  Future<void> deleteModel();

  /// مجلد تخزين النموذج على الجهاز.
  Future<String> getModelDir();

  void dispose();
}

/// منفذ التسجيل الصوتي (قابل للاستبدال للاختبار).
abstract class SpeechPort {
  SpeechEngine get engine;
  Future<bool> hasPermission();

  /// يبدأ التسجيل المتدفّق (PCM) بلا كتابة ملف.
  Future<void> start();

  /// يوقف التسجيل.
  Future<void> stop();

  /// ما سُجّل حتى الآن (أثناء التسجيل).
  WavSamples snapshot();

  /// مستوى الصوت الحالي (0..1) — للتشخيص.
  Future<double> amplitude();

  /// عيّنات ملف صوتي من المسار المعطى.
  WavSamples readSamples(String path);

  Future<void> dispose();
}

/// حالة النموذج المحلي
enum ModelStatus {
  notDownloaded,
  downloading,
  verifying,
  ready,
  error,
}

/// معلومات النموذج
class ModelInfo {
  final ModelStatus status;
  final int bytesDownloaded;
  final int bytesTotal;
  final String? error;
  final String modelDir;
  const ModelInfo({
    required this.status,
    required this.bytesDownloaded,
    required this.bytesTotal,
    required this.error,
    required this.modelDir,
  });
  double get progress => bytesTotal == 0 ? 0 : bytesDownloaded / bytesTotal;
  bool get isReady => status == ModelStatus.ready;
}

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import '../../features/speech/speech_engine.dart';
import 'wav_reader.dart';

/// تنفيذ محرّك sherpa-onnx المحلي.
class SherpaSpeechEngine implements SpeechEngine {
  sherpa_onnx.OfflineRecognizer? _recognizer;
  @override
  String get engineName => 'sherpa-onnx-moonshine-ar';

  @override
  Future<void> init({required String modelDir}) async {
    sherpa_onnx.initBindings();
    _recognizer = sherpa_onnx.OfflineRecognizer(_config(modelDir));
  }

  /// إعدادات المحرّك.
  ///
  /// **ملاحظة مهمة:** لا نستخدم `hotwordsFile` مع هذا النموذج: مفرداته على
  /// مستوى البايت، وت passing كلمات كاملة يجعل إنشاء المحرّك يفشل بالكامل
  /// ("Failed to create offline recognizer") فيتوقف التعرّف كليًّا.
  /// لا نمرر كلمات توجيه أو تصحيحًا قسريًا حتى لا تتغير تفاصيل البيع المنطوقة.
  sherpa_onnx.OfflineRecognizerConfig _config(String modelDir) {
    return sherpa_onnx.OfflineRecognizerConfig(
      model: sherpa_onnx.OfflineModelConfig(
        moonshine: sherpa_onnx.OfflineMoonshineModelConfig(
          encoder: '$modelDir/encoder_model.ort',
          mergedDecoder: '$modelDir/decoder_model_merged.ort',
        ),
        tokens: '$modelDir/tokens.txt',
        modelType: 'moonshine',
        debug: false,
        numThreads: 2,
        provider: 'cpu',
      ),
    );
  }

  @override
  Future<bool> isReady() async => _recognizer != null;

  @override
  Future<String> transcribeFile(String wavPath) async {
    final wave = TolerantWavReader.read(wavPath);
    return transcribeSamples(wave.samples, wave.sampleRate);
  }

  @override
  Future<String> transcribeSamples(Float32List samples, int sampleRate) async {
    if (_recognizer == null) throw Exception('المحرّك غير مهيأ');
    if (samples.isEmpty) return '';
    final stream = _recognizer!.createStream();
    stream.acceptWaveform(samples: samples, sampleRate: sampleRate);
    _recognizer!.decode(stream);
    final result = _recognizer!.getResult(stream);
    stream.free();
    return result.text.trim();
  }

  @override
  Future<void> setHotwords(String? hotwordsFile) async {
    // غير مدعوم مع هذا النموذج (مفرداته على مستوى البايت) ⇒ نتجاهله.
    // لا يوجد تصحيح تلقائي للنص الناتج.
  }

  @override
  Future<void> dispose() async {
    _recognizer?.free();
    _recognizer = null;
  }
}

/// تسجيل متدفّق (PCM) بلا كتابة ملف على القرص:
/// يتيح التعرّف الحيّ على الكلام أثناء التسجيل، ولا يُخزَّن أي تسجيل صوتي.
class SpeechService implements SpeechPort {
  static const int sampleRate = 16000;
  static const int channels = 1;

  final SherpaSpeechEngine _engine = SherpaSpeechEngine();
  final AudioRecorder _recorder = AudioRecorder();
  final BytesBuilder _pcm = BytesBuilder(copy: false);
  StreamSubscription<Uint8List>? _sub;

  @override
  SpeechEngine get engine => _engine;

  @override
  Future<bool> hasPermission() async => await _recorder.hasPermission();

  @override
  Future<void> start() async {
    _pcm.clear();
    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: channels,
      ),
    );
    _sub = stream.listen(_pcm.add);
    debugPrint('[WIZANO-STT] stream started (pcm16 ${sampleRate}Hz mono)');
  }

  @override
  Future<void> stop() async {
    await _recorder.stop();
    await _sub?.cancel();
    _sub = null;
  }

  /// مستوى الصوت الحالي (0..1) — للتشخيص.
  @override
  Future<double> amplitude() async {
    try {
      final value = await _recorder.getAmplitude();
      return value.current;
    } catch (_) {
      return -1;
    }
  }

  @override
  WavSamples snapshot() => WavSamples.fromPcm16(_pcm.toBytes(), sampleRate);

  @override
  WavSamples readSamples(String path) => TolerantWavReader.read(path);

  @override
  Future<void> dispose() async {
    await _sub?.cancel();
    await _recorder.dispose();
    await _engine.dispose();
  }
}




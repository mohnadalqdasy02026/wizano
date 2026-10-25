import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shop_app/features/speech/speech_controller.dart';
import 'package:shop_app/features/speech/speech_engine.dart';
import 'package:shop_app/services/speech/text_normalizer.dart';
import 'package:shop_app/services/speech/wav_reader.dart';

/// محرّك وهمي للتحقق من منطق SpeechController دون الاعتماد على نموذج حقيقي.
class _FakeEngine implements SpeechEngine {
  bool initialized = false;
  String? lastPath;
  String result = 'أرز عشرة كيلو';
  String liveResult = 'أرز عشرة';
  Object? failWith;
  int transcribeCalls = 0;
  int sampleCalls = 0;
  String Function()? provider;

  @override
  String get engineName => 'fake';

  @override
  Future<void> init({required String modelDir}) async => initialized = true;

  @override
  Future<bool> isReady() async => initialized;

  @override
  Future<String> transcribeFile(String wavPath) async {
    transcribeCalls++;
    lastPath = wavPath;
    if (failWith != null) throw failWith!;
    return provider?.call() ?? result;
  }

  @override
  Future<String> transcribeSamples(Float32List samples, int sampleRate) async {
    sampleCalls++;
    if (failWith != null) throw failWith!;
    return provider?.call() ?? result;
  }

  @override
  Future<void> setHotwords(String? hotwordsFile) async {}

  @override
  Future<void> dispose() async {}
}

/// مزوّد نموذج وهمي بحالة قابلة للضبط.
class _FakeModelProvider implements ModelProvider {
  ModelInfo _info = const ModelInfo(
    status: ModelStatus.ready,
    bytesDownloaded: 0,
    bytesTotal: 0,
    error: null,
    modelDir: '/tmp/model',
  );
  final _controller = Stream<ModelInfo>.empty();

  @override
  ModelInfo get info => _info;

  @override
  Stream<ModelInfo> get infoStream => _controller;

  set status(ModelStatus s) => _info = ModelInfo(
        status: s,
        bytesDownloaded: 0,
        bytesTotal: 0,
        error: null,
        modelDir: _info.modelDir,
      );

  @override
  Future<void> ensureReady({bool force = false}) async {}

  @override
  Future<void> deleteModel() async => status = ModelStatus.notDownloaded;

  @override
  Future<String> getModelDir() async => '/tmp/model';

  @override
  void dispose() {}
}

/// منفذ تسجيل وهمي.
class _FakeSpeechPort implements SpeechPort {
  _FakeEngine _engine = _FakeEngine();
  bool permission = true;
  bool startShouldThrow = false;
  String? recordedPath;
  WavSamples snapshotData = WavSamples(Float32List(16000), 16000);
  String liveResult = 'أرز عشرة';
  String finalResult = 'أرز عشرة كيلو';
  Object? failFinalWith;

  @override
  SpeechEngine get engine => _engine;

  set engine(_FakeEngine e) => _engine = e;

  @override
  Future<bool> hasPermission() async => permission;

  @override
  Future<void> start() async {
    if (startShouldThrow) throw StateError('mic unavailable');
    _engine.provider = () => liveResult;
  }

  @override
  Future<void> stop() async {
    if (failFinalWith != null) _engine.failWith = failFinalWith;
    _engine.provider = () => finalResult;
  }

  @override
  Future<double> amplitude() async => 0.5;

  @override
  WavSamples snapshot() => snapshotData;

  @override
  WavSamples readSamples(String path) => WavSamples(Float32List(64), 16000);

  @override
  Future<void> dispose() async {}
}

SpeechController _build({
  ModelStatus modelStatus = ModelStatus.ready,
  bool permission = true,
  bool startShouldThrow = false,
  String transcript = 'أرز عشرة كيلو',
  String liveTranscript = 'أرز عشرة',
  Object? transcribeFailsWith,
  Object? failFinalWith,
  Duration? liveInterval,
}) {
  final models = _FakeModelProvider()..status = modelStatus;
  final port = _FakeSpeechPort()
    ..permission = permission
    ..startShouldThrow = startShouldThrow
    ..liveResult = liveTranscript
    ..finalResult = transcript
    ..failFinalWith = failFinalWith;
  final engine = _FakeEngine()
    ..result = transcript
    ..liveResult = liveTranscript
    ..failWith = transcribeFailsWith;
  port.engine = engine;
  return SpeechController(
    modelManager: models,
    speechService: port,
    liveInterval: liveInterval,
  );
}

void main() {
  group('SpeechController', () {
    test('يبدأ في حالة خامل وبلا نص', () {
      final c = _build();
      expect(c.state, SpeechState.idle);
      expect(c.text, isEmpty);
      expect(c.error, isNull);
    });

    test('setText يضع النص ويحوّل الحالة إلى done', () {
      final c = _build();
      c.setText('سلطة طماطم');
      expect(c.text, 'سلطة طماطم');
      expect(c.state, SpeechState.done);
    });

    test('clear يمسح النص ويعيد الحالة إلى idle', () {
      final c = _build();
      c.setText('أرز');
      c.clear();
      expect(c.text, isEmpty);
      expect(c.state, SpeechState.idle);
    });

    test('startRecording ينجح ويحوّل الحالة إلى recording', () async {
      final c = _build();
      await c.startRecording();
      expect(c.state, SpeechState.recording);
      expect(c.error, isNull);
    });

    test('startRecording يفشل برسالة واضحة عند غياب إذن الميكروفون', () async {
      final c = _build(permission: false);
      await c.startRecording();
      expect(c.state, SpeechState.error);
      expect(c.error, contains('إذن'));
    });

    test('startRecording يرفض العمل إذا لم يكن النموذج محمّلًا', () async {
      final c = _build(modelStatus: ModelStatus.notDownloaded);
      await c.startRecording();
      expect(c.state, SpeechState.error);
      expect(c.error, contains('النموذج'));
    });

    test('startRecording يلتقط خطأ فشل بدء التسجيل', () async {
      final c = _build(startShouldThrow: true);
      await c.startRecording();
      expect(c.state, SpeechState.error);
      expect(c.error, contains('فشل بدء التسجيل'));
    });

    test('stopAndTranscribe ينجح ويعيد النص', () async {
      final c = _build(transcript: 'أرز عشرة كيلو');
      await c.startRecording();
      await c.stopAndTranscribe();
      expect(c.state, SpeechState.done);
      expect(c.text, 'أرز عشرة كيلو');
    });

    test('stopAndTranscribe يعرض رسالة خطأ ويتيح الإدخال اليدوي عند التعذّر', () async {
      final c = _build(transcribeFailsWith: StateError('decode failed'));
      await c.startRecording();
      await c.stopAndTranscribe();
      expect(c.state, SpeechState.error);
      expect(c.error, contains('تعذّر'));
      expect(c.error, contains('يدويًا'));
    });

    test('stopAndTranscribe لا يفعل شيئًا إن لم يكن التسجيل جاريًا', () async {
      final c = _build();
      await c.stopAndTranscribe();
      expect(c.state, SpeechState.idle);
    });

    test('النص الناتج بلا تشكيل', () async {
      final c = _build(transcript: 'كِيلُو سُكَّرَ . طَحِين');
      await c.startRecording();
      await c.stopAndTranscribe();
      expect(c.text, 'كيلو سكر . طحين');
    });

    test('النص الحيّ يظهر أثناء التسجيل (بلا تشكيل)', () async {
      final c = _build(
        liveTranscript: 'حُليبُ بَقِ',
        liveInterval: const Duration(milliseconds: 40),
      );
      await c.startRecording();
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(c.partial, 'حليب بق');
      expect(c.state, SpeechState.recording);
    });

    test('عند فشل التعرّف النهائي تُحفظ نتيجة التعرّف الحيّ', () async {
      final c = _build(
        liveTranscript: 'حليب بق',
        liveInterval: const Duration(milliseconds: 40),
        failFinalWith: StateError('final failed'),
      );
      await c.startRecording();
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(c.partial, 'حليب بق');
      await c.stopAndTranscribe();
      expect(c.state, SpeechState.done);
      expect(c.text, 'حليب بق');
    });
  });

  group('normalizeArabicText', () {
    test('يزيل التشكيل', () {
      expect(normalizeArabicText('كِيلُو سُكَّرَ'), 'كيلو سكر');
    });

    test('يزيل علامات قرآنية وتطويل', () {
      expect(normalizeArabicText('اللهُ'), 'الله');
      expect(normalizeArabicText('كتــاب'), 'كتاب');
    });

    test('يحوّل الأرقام العربية-الهندية إلى لاتينية', () {
      expect(normalizeArabicText('كيلو ٢'), 'كيلو 2');
      expect(normalizeArabicText('٣ كيس'), '3 كيس');
    });

    test('يوسّع المسافات ويزيل الفراغات الزائدة', () {
      expect(normalizeArabicText(' lemy   sugar  '), 'lemy sugar');
    });

    test('يترك النص الفارغ فارغًا', () {
      expect(normalizeArabicText('   '), '');
    });
  });

  group('TolerantWavReader', () {
    test('يقرأ ملف WAV صالح', () {
      final dir = Directory.systemTemp.createTempSync('wizano_wav');
      final path = '${dir.path}/a.wav';
      final pcm = List<int>.generate(320, (i) => (i % 100) * 100);
      final bytes = <int>[];
      void u32(int v) => bytes.addAll([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);
      void u16(int v) => bytes.addAll([v & 0xFF, (v >> 8) & 0xFF]);
      bytes.addAll('RIFF'.codeUnits);
      u32(36 + pcm.length);
      bytes.addAll('WAVE'.codeUnits);
      bytes.addAll('fmt '.codeUnits);
      u32(16);
      u16(1);
      u16(1);
      u32(16000);
      u32(32000);
      u16(2);
      u16(16);
      bytes.addAll('data'.codeUnits);
      u32(pcm.length);
      bytes.addAll(pcm);
      File(path).writeAsBytesSync(bytes);

      final wave = TolerantWavReader.read(path);
      expect(wave.sampleRate, 16000);
      expect(wave.samples.length, 160);
      dir.deleteSync(recursive: true);
    });

    test('يتعامل مع ملف غير موجود أو تالف دون أن يرمي', () {
      expect(TolerantWavReader.read('C:\\missing\\none.wav').samples.isEmpty, isTrue);
    });
  });
}



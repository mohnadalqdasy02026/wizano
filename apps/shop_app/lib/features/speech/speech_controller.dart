import 'dart:async';
import 'dart:io';

import '../../services/speech/wav_reader.dart';

import 'package:flutter/foundation.dart';

import '../../services/speech/text_normalizer.dart';
import '../../services/speech/system_speech_service.dart';
import 'speech_engine.dart';

enum SpeechState { idle, recording, processing, done, error }

class SpeechController extends ChangeNotifier {
  final ModelProvider modelManager;
  final SpeechPort speechService;
  final SystemSpeechService systemSpeech;
  SpeechController({
    required this.modelManager,
    required this.speechService,
    SystemSpeechService? systemSpeech,
    Duration? liveInterval,
  })  : systemSpeech = systemSpeech ?? SystemSpeechService(),
        _liveIntervalValue = liveInterval ?? _liveInterval {
    // فحص النموذج على القرص عند الإقلاع: بدونه يظنّ التطبيق أن النموذج
    // غير محمّل بعد كل إعادة تشغيل، فيطلب تنزيله من جديد.
    unawaited(ensureModel());
  }

  /// أقل مدة تسجيل (بالثواني) قبل عرض رسالة «لم أسمع كلامًا واضحًا».
  static const Duration minRecording = Duration(milliseconds: 700);

  /// فاصل إعادة فكّ الترميز أثناء التسجيل (يظهر النص حيًّا).
  static const Duration _liveInterval = Duration(milliseconds: 1400);

  /// أقصى نافذة صوتية تُحلَّل في العرض الحيّ (بالثواني).
  /// يحدّ من زمن المعالجة كلما طال التسجيل فتبقى الواجهة سلسة.
  static const int _liveWindowSeconds = 10;

  Duration _liveIntervalValue;

  SpeechState _state = SpeechState.idle;
  SpeechState get state => _state;
  String _text = '';
  String get text => _text;
  String _partial = '';
  String get partial => _partial;
  String? _error;
  String? get error => _error;
  String? _lastPath;
  String? get lastPath => _lastPath;

  Timer? _liveTimer;
  bool _busyDecoding = false;
  StreamSubscription<SystemSpeechEvent>? _systemSubscription;
  Completer<String>? _systemResult;
  bool _usingSystemRecognizer = false;

  /// هل خدمة Android عالية الدقة متاحة على هذا الهاتف؟
  /// لا تعني أن الإنترنت متصل؛ عند فشل الشبكة نرجع للمحرك المحلي.
  Future<bool> canUseHighAccuracyRecognition() => systemSpeech.isAvailable();

  Future<void> ensureModel() async {
    try {
      await modelManager.ensureReady();
      if (modelManager.info.isReady && !(await speechService.engine.isReady())) {
        await speechService.engine.init(modelDir: modelManager.info.modelDir);
      }
    } catch (e) {
      debugPrint('[WIZANO-STT] ensureModel failed: $e');
      // فحص النموذج عند تشغيل التطبيق استباقي فقط. لا نعرض خطأً أحمر
      // للمستخدم قبل أن يضغط زر التسجيل؛ سيظهر الخطأ الواضح عند الطلب فقط.
      // يبقى زر التسجيل قادرًا على إعادة محاولة تهيئة المحرك بنفسه.
    }
  }

  bool _vocabularyEnabled = false;

  /// تفعيل/تعطيل تصحيح الأخطاء بمفردات المحل بعد التعرّف.
  bool get vocabularyEnabled => _vocabularyEnabled;

  Future<void> setVocabularyEnabled(bool enabled) async {
    if (_vocabularyEnabled == enabled) return;
    _vocabularyEnabled = enabled;
    notifyListeners();
  }

  /// متوافق مع الاستدعاءات القديمة؛ لا يجري أي تعديل على النص المنطوق.
  Future<void> setShopTerms(Iterable<String> itemsTexts) async {}

  /// تنظيف بصري للناتج فقط: يحذف التشكيل دون تصحيح أو استبدال أي كلمة.
  /// هذه قاعدة مهمة للبيانات المالية: لا يجوز للتطبيق تغيير ما قاله المستخدم.
  String _verbatim(String text) => cleanSpeechTranscript(text);

  /// يقيس مستوى الصوت المسجَّل (جذر متوسط المربعات) — للتشخيص.
  static double _rms(Float32List samples) {
    if (samples.isEmpty) return 0;
    var sum = 0.0;
    for (final s in samples) {
      sum += s * s;
    }
    return _sqrt(sum / samples.length);
  }

  static double _sqrt(double value) {
    if (value <= 0) return 0;
    var guess = value;
    for (var i = 0; i < 12; i++) {
      guess = 0.5 * (guess + value / guess);
    }
    return guess;
  }

  Future<void> startRecording() async {
    _error = null;
    _partial = '';
    final ok = await speechService.hasPermission();
    if (!ok) {
      _error = 'لا يوجد إذن للميكروفون';
      _state = SpeechState.error;
      notifyListeners();
      return;
    }
    // محرك Android يستعمل خدمة التعرف المثبّتة في الهاتف عند وجود الإنترنت.
    // لا نستخدم أي تصحيح أو قاموس بعد النتيجة؛ النص يبقى كما أعادته الخدمة.
    if (await systemSpeech.isAvailable()) {
      try {
        _usingSystemRecognizer = true;
        _systemResult = Completer<String>();
        await _systemSubscription?.cancel();
        _systemSubscription = systemSpeech.events.listen(_onSystemSpeechEvent);
        await systemSpeech.start();
        _state = SpeechState.recording;
        notifyListeners();
        return;
      } catch (e) {
        // الخدمة موجودة لكن تعذر فتحها الآن؛ نستمر بالمحرك المحلي بدل تعطل الزر.
        _usingSystemRecognizer = false;
        await _systemSubscription?.cancel();
        _systemSubscription = null;
      }
    }
    if (!modelManager.info.isReady) {
      _error = 'النموذج غير محمّل. نزّله من الإعدادات أولًا';
      _state = SpeechState.error;
      notifyListeners();
      return;
    }
    if (!await speechService.engine.isReady()) {
      try {
        await speechService.engine.init(modelDir: modelManager.info.modelDir);
      } catch (e) {
        _error = 'فشل تهيئة محرّك التعرف: $e';
        _state = SpeechState.error;
        notifyListeners();
        return;
      }
    }
    try {
      await speechService.start();
      _state = SpeechState.recording;
      // نبدأ المؤقّت قبل إشعار الواجهة: أي خطأ في إعادة البناء لا يوقف التعرّف الحيّ.
      _startLiveTimer();
      notifyListeners();
    } catch (e) {
      _error = 'فشل بدء التسجيل: $e';
      _state = SpeechState.error;
      notifyListeners();
    }
  }

  void _onSystemSpeechEvent(SystemSpeechEvent event) {
    if (event.type == 'partial') {
      final text = _verbatim(event.text);
      if (text.isNotEmpty && text != _partial) {
        _partial = text;
        notifyListeners();
      }
      return;
    }
    if (event.type == 'final') {
      final text = _verbatim(event.text);
      if (text.isNotEmpty) {
        _text = text;
        _partial = text;
        if (!(_systemResult?.isCompleted ?? true)) _systemResult!.complete(text);
      } else if (!(_systemResult?.isCompleted ?? true)) {
        _systemResult!.completeError('لم أسمع كلامًا واضحًا');
      }
      notifyListeners();
      return;
    }
    if (event.type == 'error' && !(_systemResult?.isCompleted ?? true)) {
      _systemResult!.completeError(event.message.isEmpty
          ? 'تعذر التعرف عبر خدمة الهاتف'
          : event.message);
    }
  }

  void _startLiveTimer() {
    _liveTimer?.cancel();
    debugPrint('[WIZANO-STT] live timer started (${_liveIntervalValue.inMilliseconds}ms)');
    _liveTimer = Timer.periodic(_liveIntervalValue, (_) => _decodePartial());
  }

  /// يعيد ضبط فاصل التعرّف الحيّ حسب سرعة الجهاز: الأجهزة الضعيفة
  /// (المحاكي) تستقبل فاصلًا أطول، والسريعة فاصلًا أقصر.
  void _adaptLiveInterval(Duration elapsed) {
    if (elapsed.inMilliseconds > 900) {
      _liveIntervalValue = const Duration(milliseconds: 3000);
    } else if (elapsed.inMilliseconds < 350) {
      _liveIntervalValue = const Duration(milliseconds: 1200);
    } else {
      _liveIntervalValue = const Duration(milliseconds: 1800);
    }
    if (_state == SpeechState.recording) {
      _startLiveTimer();
    }
  }

  /// فكّ ترميز ما سُجّل حتى الآن لعرضه حيًّا أثناء الكلام.
  Future<void> _decodePartial() async {
    if (_state != SpeechState.recording) return;
    if (_busyDecoding) return;
    _busyDecoding = true;
    final started = DateTime.now();
    try {
      final wave = speechService.snapshot();
      debugPrint('[WIZANO-STT] live tick: samples=${wave.samples.length} '
          'dur=${wave.durationSeconds.toStringAsFixed(2)} '
          'rms=${_rms(wave.samples).toStringAsFixed(4)}');
      if (wave.isEmpty || wave.durationSeconds < 0.6) return;
      // نحلّل آخر جزء فقط من الصوت حتى لا تتراكم المعالجة مع طول التسجيل.
      final windowSamples = wave.sampleRate * _liveWindowSeconds;
      final samples = wave.samples.length <= windowSamples
          ? wave.samples
          : Float32List.sublistView(
              wave.samples,
              wave.samples.length - windowSamples,
            );
      final raw = await speechService.engine.transcribeSamples(samples, wave.sampleRate);
      final text = _verbatim(raw);
      if (text.isEmpty) return;
      if (text == _partial) return;
      _partial = text;
      notifyListeners();
    } catch (e) {
      debugPrint('[WIZANO-STT] live error: $e');
    } finally {
      _busyDecoding = false;
      _adaptLiveInterval(DateTime.now().difference(started));
    }
  }

  Future<void> stopAndTranscribe() async {
    if (_state != SpeechState.recording) return;
    if (_usingSystemRecognizer) {
      _state = SpeechState.processing;
      notifyListeners();
      try {
        await systemSpeech.stop();
        final text = await (_systemResult?.future ?? Future<String>.value(''))
            .timeout(const Duration(seconds: 12));
        _text = text;
        _state = SpeechState.done;
      } catch (_) {
        // عند تعذر خدمة الهاتف (غالبًا انقطاع الإنترنت) لا نخترع نصًا من
        // المحرك المحلي؛ نعرض آخر نتيجة جزئية فقط إن كانت موجودة.
        if (_partial.isNotEmpty) {
          _text = _partial;
          _state = SpeechState.done;
        } else {
          _error = 'تعذّر التعرف عالي الدقة. تحقق من الإنترنت أو أعد المحاولة، ويمكنك استخدام الإدخال اليدوي.';
          _state = SpeechState.error;
        }
      } finally {
        _usingSystemRecognizer = false;
        await _systemSubscription?.cancel();
        _systemSubscription = null;
        notifyListeners();
      }
      return;
    }
    _liveTimer?.cancel();
    _liveTimer = null;
    _state = SpeechState.processing;
    notifyListeners();
    try {
      await speechService.stop();
      final wave = speechService.snapshot();
      final text = await _decodeInChunks(wave);
      debugPrint('[WIZANO-STT] final: samples=${wave.samples.length} '
          'text="$text" partial="$_partial"');
      if (text.isEmpty) {
        if (_partial.isNotEmpty) {
          _text = _partial;
          _state = SpeechState.done;
          notifyListeners();
          return;
        }
        _error = 'لم أسمع كلامًا واضحًا. تأكد من الميكروفون وتحدّث بصوت أعلى، أو أدخل التفاصيل يدويًا.';
        _state = SpeechState.error;
        notifyListeners();
        return;
      }
      _text = text;
      _state = SpeechState.done;
      notifyListeners();
    } catch (e) {
      if (_partial.isNotEmpty) {
        _text = _partial;
        _state = SpeechState.done;
        notifyListeners();
        return;
      }
      _error = 'تعذّر التعرف على الكلام. جرب مرة أخرى أو أدخل النص يدويًا.\n$e';
      _state = SpeechState.error;
      notifyListeners();
    }
  }

  /// يفكّ ترميز التسجيل كاملًا على دفعات، ويحدّث النص بعد كل دفعة.
  /// الدفعات تقصّر زمن التوقّف المتواصل للواجهة (فكّ الترميز متزامن).
  Future<String> _decodeInChunks(WavSamples wave) async {
    if (wave.isEmpty) return '';
    final chunkSize = wave.sampleRate * _liveWindowSeconds;
    if (wave.samples.length <= chunkSize) {
      final raw = await speechService.engine.transcribeSamples(
        wave.samples,
        wave.sampleRate,
      );
      return _verbatim(raw);
    }
    final buffer = StringBuffer();
    for (var offset = 0; offset < wave.samples.length; offset += chunkSize) {
      final end = (offset + chunkSize).clamp(0, wave.samples.length).toInt();
      final chunk = Float32List.sublistView(wave.samples, offset, end);
      final raw = await speechService.engine.transcribeSamples(
        chunk,
        wave.sampleRate,
      );
      final piece = _verbatim(raw);
      if (piece.isNotEmpty) {
        if (buffer.isNotEmpty) buffer.write('\n');
        buffer.write(piece);
      }
      // تحديث تدريجي: المستخدم يرى النص وهو يُكتب.
      _text = buffer.toString();
      notifyListeners();
    }
    return buffer.toString();
  }

  /// تحويل ملف صوتي محلي إلى نص باستخدام المحرك المحلي.
  Future<void> transcribePath(String path) async {
    _error = null;
    _state = SpeechState.processing;
    notifyListeners();
    try {
      if (!await speechService.engine.isReady()) {
        await speechService.engine.init(modelDir: modelManager.info.modelDir);
      }
      if (!await File(path).exists()) {
        throw Exception('ملف الصوت غير موجود');
      }
      _lastPath = path;
      final wave = speechService.readSamples(path);
      final raw = wave.isEmpty
          ? await speechService.engine.transcribeFile(path)
          : await speechService.engine.transcribeSamples(wave.samples, wave.sampleRate);
      final text = _verbatim(raw);
      debugPrint('[WIZANO-STT] file decode: samples=${wave.samples.length} text="$text"');
      if (text.isEmpty) {
        _error = 'لم أسمع كلامًا واضحًا';
        _state = SpeechState.error;
        notifyListeners();
        return;
      }
      _text = text;
      _state = SpeechState.done;
      notifyListeners();
    } catch (e) {
      _error = 'تعذّر التعرف على الكلام. جرب مرة أخرى أو أدخل النص يدويًا.\n$e';
      _state = SpeechState.error;
      notifyListeners();
    }
  }

  void setText(String t) {
    _text = t;
    _state = SpeechState.done;
    notifyListeners();
  }

  void clear() {
    _text = '';
    _partial = '';
    _error = null;
    _state = SpeechState.idle;
    notifyListeners();
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    _systemSubscription?.cancel();
    unawaited(systemSpeech.cancel());
    speechService.dispose();
    modelManager.dispose();
    super.dispose();
  }
}














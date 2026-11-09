import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../features/speech/speech_engine.dart';
import 'model_extractor.dart';

/// يتحقق أن الملف موجود **وقابل للقراءة** فعلًا.
///
/// وجود الاسم في المجلد لا يعني أن التطبيق يستطيع قراءته: النموذج القديم
/// كان يُنسخ إلى مساحة مشتركة (`Documents`) بينما التطبيق بلا صلاحية تخزين،
/// فيمرّر sherpa-onnx المسار إلى فتح أصلي يعيد الوصف `-1` ثم يُجهض العملية
/// بـ`SIGABRT` بدل رمي استثناء Dart. الفحص هنا يمنع الوصول إلى تلك الحالة.
Future<bool> _isReadableFile(String path) async {
  try {
    final file = File(path);
    if (!await file.exists()) return false;
    final raf = await file.open(mode: FileMode.read);
    try {
      return await raf.length() > 0;
    } finally {
      await raf.close();
    }
  } catch (_) {
    return false;
  }
}

Future<Directory> _defaultBaseDir() async {
  // نحاول حفظ النموذج في تخزين عام (يبقى بعد إلغاء التثبيت).
  for (final candidate in const [
    '/storage/emulated/0/Documents/Wizano',
    '/sdcard/Documents/Wizano',
  ]) {
    try {
      final d = Directory(candidate);
      await d.create(recursive: true);
      final test = File('${d.path}/.wizano_write_test');
      await test.writeAsString('ok');
      await test.delete();
      return d;
    } catch (_) {
      // fallback
    }
  }
  // ثم التخزين الخارجي الخاص بالتطبيق: مضمون الكتابة، ويبقى حتى مسح بيانات
  // التطبيق (وليس إلغاء تثبيته). كان السابق يعود للتخزين الداخلي مباشرة
  // فيفقد إمكانية نقل النموذج إلى الجهاز عبر USB.
  try {
    final external = await getExternalStorageDirectory();
    if (external != null) {
      await external.create(recursive: true);
      return external;
    }
  } catch (_) {
    // fallback
  }
  return getApplicationSupportDirectory();
}

/// مدير تنزيل نموذج Whisper العربي المحلي.
/// النموذج يعمل 100% دون اتصال بعد التنزيل. لا يُرسل صوت للخارج.
class ModelManager implements ModelProvider {
  static const String modelName = 'sherpa-onnx-whisper-base';
  static const String modelUrl = 'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/$modelName.tar.bz2';

  ModelManager({
    Future<Directory> Function()? baseDirProvider,
    String? modelUrl,
  })  : _baseDirProvider = baseDirProvider ?? _defaultBaseDir,
        _modelUrl = modelUrl ?? ModelManager.modelUrl;

  /// مجلد التطبيق الذي تُحفظ النماذج داخله (قابل للاستبدال في الاختبار).
  final Future<Directory> Function() _baseDirProvider;

  /// رابط النموذج (قابل للاستبدال في الاختبار).
  final String _modelUrl;

  final _controller = StreamController<ModelInfo>.broadcast();
  @override
  Stream<ModelInfo> get infoStream => _controller.stream;

  ModelInfo _info = const ModelInfo(status: ModelStatus.notDownloaded, bytesDownloaded: 0, bytesTotal: 0, error: null, modelDir: '');
  @override
  ModelInfo get info => _info;
  String? _modelDir;

  @override
  Future<String> getModelDir() async {
    if (_modelDir != null) return _modelDir!;
    final dir = await _baseDirProvider();
    _modelDir = '${dir.path}/models/$modelName';
    return _modelDir!;
  }

  @override
  Future<void> checkReady() async {
    final dir = await getModelDir();
    final dirObj = Directory(dir);
    await dirObj.parent.create(recursive: true);
    if (await _isComplete(dirObj)) {
      _info = ModelInfo(
        status: ModelStatus.ready,
        bytesDownloaded: 0,
        bytesTotal: 0,
        error: null,
        modelDir: dir,
      );
      _controller.add(_info);
      return;
    }
    final legacyDir = await _findLegacyDir(dirObj);
    _info = ModelInfo(
      status: legacyDir != null ? ModelStatus.ready : ModelStatus.notDownloaded,
      bytesDownloaded: 0,
      bytesTotal: 0,
      error: null,
      modelDir: legacyDir ?? '',
    );
    _controller.add(_info);
  }

  @override
  Future<void> ensureReady({bool force = false}) async {
    final dir = await getModelDir();
    final dirObj = Directory(dir);
    // نضمن وجود مجلد النماذج حتى على التثبيت الجديد.
    await dirObj.parent.create(recursive: true);
    final complete = await _isComplete(dirObj);
    debugPrint('[WIZANO-STT] ensureReady dir=$dir complete=$complete force=$force');
    if (!force && complete) {
      _info = ModelInfo(status: ModelStatus.ready, bytesDownloaded: 0, bytesTotal: 0, error: null, modelDir: dir);
      _controller.add(_info);
      return;
    }
    // نموذج عربي سابق مكتمل: نستخدمه بدل إجبار المستخدم على تنزيل نموذج
    // جديد قد لا يكتمل على شبكة بطيئة. التنزيل القسري (force) يبقى متاحًا.
    if (!force) {
      final legacyDir = await _findLegacyDir(dirObj);
      if (legacyDir != null) {
        debugPrint('[WIZANO-STT] using legacy model at $legacyDir');
        _info = ModelInfo(
          status: ModelStatus.ready,
          bytesDownloaded: 0,
          bytesTotal: 0,
          error: null,
          modelDir: legacyDir,
        );
        _controller.add(_info);
        return;
      }
    }
    await _download(dir);
  }

  /// يبحث عن نموذج عربي قديم مكتمل في المواقع المعروفة.
  ///
  /// لا نكتفي بمجلد التخزين الحالي: بعض الأجهزة تحتوي النموذج في مساحة
  /// عامة بينما تعذّر الكتابة فيها، فيعود التطبيق إلى التخزين الداخلي
  /// ويكرر تنزيل 200MB بلا داعٍ.
  Future<String?> _findLegacyDir(Directory whisperDir) async {
    final candidates = <String>{
      '${whisperDir.parent.path}/$legacyModelName',
      '/storage/emulated/0/Documents/Wizano/models/$legacyModelName',
      '/sdcard/Documents/Wizano/models/$legacyModelName',
    };
    try {
      final external = await getExternalStorageDirectory();
      if (external != null) {
        candidates.add('${external.path}/models/$legacyModelName');
      }
    } catch (_) {
      // لا يوجد تخزين خارجي على هذا الجهاز.
    }
    for (final path in candidates) {
      try {
        if (await _isCompleteWith(path, legacyModelRequiredFiles)) {
          return path;
        }
      } catch (_) {
        // مسار غير متاح على هذا الجهاز: نجرّب التالي.
      }
    }
    return null;
  }

  Future<bool> _isComplete(Directory dir) =>
      _isCompleteWith(dir.path, modelRequiredFiles);

  Future<bool> _isCompleteWith(String path, List<String> files) async {
    try {
      if (!await Directory(path).exists()) return false;
    } catch (_) {
      return false;
    }
    for (final name in files) {
      if (!await _isReadableFile('$path/$name')) {
        debugPrint('[WIZANO-STT] unreadable model file: $path/$name');
        return false;
      }
    }
    return true;
  }

  Future<void> _download(String dir) async {
    final dirObj = Directory(dir);
    final parent = dirObj.parent;
    // نُنزّل إلى مجلد مؤقت، ولا نستبدل النموذج الموجود إلا بعد نجاح الفكّ
    // والتحقق؛ فالتنزيل الفاشل لا يُتلف نموذجًا يعمل بالفعل.
    final tmpDir = '${parent.path}/.tmp';

    try {
      // مجلد التنزيل يجب أن exists قبل فتح الملف (تثبيت جديد بلا مجلد models).
      await parent.create(recursive: true);
      debugPrint('[WIZANO-STT] download start url=$_modelUrl');
      final req = http.Request('GET', Uri.parse(_modelUrl));
      final resp = await http.Client().send(req);
      final total = resp.contentLength ?? 0;
      debugPrint('[WIZANO-STT] response status=${resp.statusCode} total=$total');
      _info = ModelInfo(status: ModelStatus.downloading, bytesDownloaded: 0, bytesTotal: total, error: null, modelDir: '');
      _controller.add(_info);
      final tarPath = '${parent.path}/$modelName.tar.bz2';
      final file = File(tarPath);
      final sink = file.openWrite();
      int received = 0;
      await for (final chunk in resp.stream) {
        sink.add(chunk);
        received += chunk.length;
        _info = ModelInfo(status: ModelStatus.downloading, bytesDownloaded: received, bytesTotal: total, error: null, modelDir: '');
        _controller.add(_info);
      }
      await sink.close();
      debugPrint('[WIZANO-STT] download done bytes=$received');

      _info = ModelInfo(status: ModelStatus.verifying, bytesDownloaded: 0, bytesTotal: 0, error: null, modelDir: dir);
      _controller.add(_info);

      // نفكّ الضغط على القرص تدفّقيًا: الأرشيف نحو 100MB ولا يصح تحميله
      // كاملًا في الذاكرة ثم فكّه فيها (كان يسبّب فشلًا بعد اكتمال التنزيل).
      final ok = await extractModelArchiveFromFile(
        archivePath: tarPath,
        targetDir: tmpDir,
        modelName: modelName,
        requiredFiles: modelRequiredFiles,
      );
      if (!ok) {
        throw Exception('النموذج غير كامل بعد التنزيل');
      }
      if (await File(tarPath).exists()) await File(tarPath).delete();

      // الاستبدال الآن فقط بعد نجاح كل الخطوات.
      if (await dirObj.exists()) {
        await dirObj.delete(recursive: true);
      }
      await Directory(tmpDir).rename(dir);

      _info = ModelInfo(status: ModelStatus.ready, bytesDownloaded: 0, bytesTotal: 0, error: null, modelDir: dir);
      _controller.add(_info);
    } catch (e) {
      debugPrint('[WIZANO-STT] download failed: $e');
      final tmp = Directory(tmpDir);
      if (await tmp.exists()) {
        try {
          await tmp.delete(recursive: true);
        } catch (_) {}
      }
      // تنظيف الأرشيف الجزئي (قد يكون 119MB) حتى لا يملأ مساحة الجهاز.
      try {
        final tar = File('${parent.path}/$modelName.tar.bz2');
        if (await tar.exists()) await tar.delete();
      } catch (_) {}
      final stillReady = await _isComplete(dirObj);
      _info = ModelInfo(
        status: stillReady ? ModelStatus.ready : ModelStatus.error,
        bytesDownloaded: 0,
        bytesTotal: 0,
        error: stillReady ? null : e.toString(),
        modelDir: dir,
      );
      _controller.add(_info);
      rethrow;
    }
  }

  @override
  Future<void> deleteModel() async {
    final dir = await getModelDir();
    final parent = Directory(dir).parent;
    for (final target in [dir, '${parent.path}/$legacyModelName']) {
      final d = Directory(target);
      if (await d.exists()) await d.delete(recursive: true);
    }
    _info = const ModelInfo(status: ModelStatus.notDownloaded, bytesDownloaded: 0, bytesTotal: 0, error: null, modelDir: '');
    _controller.add(_info);
  }

  @override
  void dispose() {
    _controller.close();
  }
}

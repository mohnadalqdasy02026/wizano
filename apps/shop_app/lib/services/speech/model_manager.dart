import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../features/speech/speech_engine.dart';
import 'model_extractor.dart';

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
  return getApplicationSupportDirectory();
}

/// مدير تنزيل نموذج sherpa-onnx العربي محليًا.
/// النموذج يعمل 100% دون اتصال بعد التنزيل. لا يُرسل صوت للخارج.
class ModelManager implements ModelProvider {
  static const String modelName = 'sherpa-onnx-moonshine-base-ar-quantized-2026-02-27';
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
    await _download(dir);
  }

  Future<bool> _isComplete(Directory dir) async {
    if (!await dir.exists()) return false;
    final enc = File('${dir.path}/encoder_model.ort');
    final dec = File('${dir.path}/decoder_model_merged.ort');
    final tok = File('${dir.path}/tokens.txt');
    return await enc.exists() && await dec.exists() && await tok.exists();
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

      final input = File(tarPath).readAsBytesSync();
      final ok = await extractModelArchive(
        compressedBytes: input,
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
    final d = Directory(dir);
    if (await d.exists()) await d.delete(recursive: true);
    _info = const ModelInfo(status: ModelStatus.notDownloaded, bytesDownloaded: 0, bytesTotal: 0, error: null, modelDir: '');
    _controller.add(_info);
  }

  @override
  void dispose() {
    _controller.close();
  }
}

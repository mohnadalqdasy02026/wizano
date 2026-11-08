import 'dart:io';

import 'package:archive/archive_io.dart';

/// فكّ ضغط أرشيف النموذج (tar.bz2) من الذاكرة إلى مجلد الهدف.
///
/// تُستخدم في الاختبارات أو لأرشيفات صغيرة. على الجهاز استخدم
/// [extractModelArchiveFromFile] لأن أرشيف Whisper كبير (نحو 100MB) ولا
/// يجوز تحميله كاملًا في الذاكرة.
Future<bool> extractModelArchive({
  required List<int> compressedBytes,
  required String targetDir,
  required String modelName,
  required List<String> requiredFiles,
}) async {
  final tarBytes = BZip2Decoder().decodeBytes(compressedBytes);
  final archive = TarDecoder().decodeBytes(tarBytes);
  await _extractEntries(
    archive: archive,
    targetDir: targetDir,
    modelName: modelName,
  );
  return _hasRequiredFiles(targetDir, requiredFiles);
}

/// فكّ ضغط الأرشيف إلى قرصه مباشرة ثم استخراج ملفات النموذج فقط.
///
/// يحافظ على استهلاك ذاكرة منخفض (chunk واحد في كل مرة) بدل تحميل الأرشيف
/// كاملًا ثم فكّه في الذاكرة — وهو ما كان يسبّب فشل التنزيل أو نفاد الذاكرة
/// على الأجهزة المتوسطة بعد اكتمال التحميل.
///
/// [archivePath] ملف tar.bz2 المنزَّل، ويُحذف بعد فكّ ضغطه.
Future<bool> extractModelArchiveFromFile({
  required String archivePath,
  required String targetDir,
  required String modelName,
  required List<String> requiredFiles,
}) async {
  final tarPath = '$archivePath.extracting.tar';
  try {
    // 1) فكّ bz2 إلى ملف tar على القرص (تدفّقيًا).
    final input = InputFileStream(archivePath);
    final output = OutputFileStream(tarPath, bufferSize: 1024 * 1024);
    try {
      BZip2Decoder().decodeStream(input, output);
    } finally {
      input.closeSync();
      output.closeSync();
    }

    // لم نعد بحاجة للأرشيف المضغوط بعد فكّه.
    try {
      await File(archivePath).delete();
    } catch (_) {
      // الحذف تحسين للمساحة فقط.
    }

    // 2) قراءة فهرس tar من الملف (لا يُحمَّل المحتوى في الذاكرة).
    final tarInput = InputFileStream(tarPath);
    try {
      final archive = TarDecoder().decodeBuffer(tarInput);
      await _extractEntries(
        archive: archive,
        targetDir: targetDir,
        modelName: modelName,
      );
    } finally {
      tarInput.closeSync();
    }
  } finally {
    try {
      final tar = File(tarPath);
      if (await tar.exists()) await tar.delete();
    } catch (_) {
      // تنظيف أفضل-جهد.
    }
  }

  return _hasRequiredFiles(targetDir, requiredFiles);
}

/// يستخرج ملفات [modelName] فقط داخل [targetDir]، مع كتابة تدفّقية لكل ملف.
Future<void> _extractEntries({
  required Archive archive,
  required String targetDir,
  required String modelName,
}) async {
  final target = Directory(targetDir);
  if (await target.exists()) {
    await target.delete(recursive: true);
  }
  await target.create(recursive: true);

  final prefix = '$modelName/';
  for (final entry in archive) {
    final name = entry.name.replaceAll('\\', '/');
    if (!name.startsWith(prefix)) continue;
    final rel = name.substring(prefix.length);
    if (rel.isEmpty) continue;
    // حماية من مسارات الخروج عن المجلد الهدف (../ أو مسار مطلق).
    if (rel.startsWith('/') || rel.split('/').contains('..')) continue;

    final outPath = '${target.path}/$rel';
    if (entry.isFile) {
      final raw = entry.rawContent;
      if (raw == null) continue;
      await File(outPath).parent.create(recursive: true);
      final fileOutput = OutputFileStream(outPath, bufferSize: 1024 * 1024);
      try {
        // OutputFileStream يكتب InputStreamBase على شكل قطع بحجم 1MB،
        // فلا تُحمَّل ملفات النموذج الكبيرة كاملة في الذاكرة.
        fileOutput.writeInputStream(raw);
      } finally {
        await fileOutput.close();
      }
      entry.clear();
    } else {
      await Directory(outPath).create(recursive: true);
    }
  }
}

Future<bool> _hasRequiredFiles(
  String targetDir,
  List<String> requiredFiles,
) async {
  for (final required in requiredFiles) {
    if (!await File('$targetDir/$required').exists()) return false;
  }
  return true;
}

/// أسماء الملفات المطلوبة لجاهزية النموذج.
///
/// **مهم:** يجب أن تطابق أسماء الملفات الحقيقية داخل أرشيف
/// `sherpa-onnx-whisper-base` وأسماء الملفات التي يفتحها محرك التعرف.
/// أي اختلاف هنا يجعل التنزيل يكتمل ثم يُعلن «فشل التحميل» بلا سبب ظاهر.
const List<String> modelRequiredFiles = [
  'base-encoder.int8.onnx',
  'base-decoder.int8.onnx',
  'base-tokens.txt',
];

/// النموذج العربي السابق (Moonshine) الذي كان التطبيق يستخدمه.
///
/// بقي على أجهزة كثيرة بعد الترقية إلى Whisper. إجبار المستخدم على تنزيل
/// ‏200MB جديدة على شبكة بطيئة يعني تعطّل الإدخال الصوتي بلا سبب، فنقبل
/// النموذج القديم إن كان مكتملًا ونستخدمه.
const String legacyModelName =
    'sherpa-onnx-moonshine-base-ar-quantized-2026-02-27';

const List<String> legacyModelRequiredFiles = [
  'encoder_model.ort',
  'decoder_model_merged.ort',
  'tokens.txt',
];


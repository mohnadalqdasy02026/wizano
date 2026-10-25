import 'dart:io';

import 'package:archive/archive_io.dart';

/// فكّ ضغط أرشيف النموذج (tar.bz2) إلى مجلد الهدف.
/// دالة خالصة (بلا اعتماد على plugins) حتى يمكن اختبارها وحدويًا.
/// تُرجع true عند استخراج كل الملفات المطلوبة بنجاح.
Future<bool> extractModelArchive({
  required List<int> compressedBytes,
  required String targetDir,
  required String modelName,
  required List<String> requiredFiles,
}) async {
  final tarBytes = BZip2Decoder().decodeBytes(compressedBytes);
  final archive = TarDecoder().decodeBytes(tarBytes);
  final target = Directory(targetDir);
  if (await target.exists()) {
    await target.delete(recursive: true);
  }
  await target.create(recursive: true);

  for (final entry in archive) {
    final name = entry.name;
    if (!name.startsWith('$modelName/')) continue;
    final rel = name.substring('$modelName/'.length);
    if (rel.isEmpty) continue;
    final outFile = File('${target.path}/$rel');
    if (entry.isFile) {
      await outFile.create(recursive: true);
      await outFile.writeAsBytes(entry.content as List<int>);
    } else {
      await Directory(outFile.path).create(recursive: true);
    }
  }

  for (final required in requiredFiles) {
    if (!await File('${target.path}/$required').exists()) return false;
  }
  return true;
}

/// أسماء الملفات المطلوبة لجاهزية النموذج.
const List<String> modelRequiredFiles = [
  'encoder_model.ort',
  'decoder_model_merged.ort',
  'tokens.txt',
];

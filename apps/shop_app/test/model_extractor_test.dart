import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_app/services/speech/model_extractor.dart';

/// يبني أرشيف tar.bz2 اصطناعيًا بنفس بنية أرشيف النموذج الحقيقي:
/// مجلد جذر باسم النموذج يحوي الملفات المطلوبة.
List<int> _buildFakeArchive(String modelName) {
  final archive = Archive();
  archive.addFile(ArchiveFile('$modelName/encoder_model.ort', 4, 'enc!'.codeUnits));
  archive.addFile(ArchiveFile('$modelName/decoder_model_merged.ort', 4, 'dec!'.codeUnits));
  archive.addFile(ArchiveFile('$modelName/tokens.txt', 4, 'tok!'.codeUnits));
  archive.addFile(ArchiveFile('$modelName/test_wavs/0.wav', 4, 'wav!'.codeUnits));
  archive.addFile(ArchiveFile('other/ignore.txt', 4, 'ign!'.codeUnits));

  final tarBytes = TarEncoder().encode(archive);
  return BZip2Encoder().encode(tarBytes);
}

void main() {
  group('extractModelArchive', () {
    test('يستخرج ملفات النموذج المطلوبة ويتجاهل ما خارج المجلد', () async {
      const modelName = 'test-model-ar';
      final dir = Directory.systemTemp.createTempSync('wizano_extract');
      final target = '${dir.path}/$modelName';

      final ok = await extractModelArchive(
        compressedBytes: _buildFakeArchive(modelName),
        targetDir: target,
        modelName: modelName,
        requiredFiles: modelRequiredFiles,
      );

      expect(ok, isTrue);
      expect(File('$target/encoder_model.ort').existsSync(), isTrue);
      expect(File('$target/decoder_model_merged.ort').existsSync(), isTrue);
      expect(File('$target/tokens.txt').existsSync(), isTrue);
      expect(File('$target/test_wavs/0.wav').existsSync(), isTrue);
      expect(File('$target/other/ignore.txt').existsSync(), isFalse);

      expect(
        File('$target/encoder_model.ort').readAsStringSync(),
        'enc!',
      );
      expect(
        File('$target/tokens.txt').readAsStringSync(),
        'tok!',
      );

      dir.deleteSync(recursive: true);
    });

    test('يرجع false عند نقص ملف مطلوب', () async {
      const modelName = 'test-model-ar';
      final dir = Directory.systemTemp.createTempSync('wizano_extract');
      final target = '${dir.path}/$modelName';

      final ok = await extractModelArchive(
        compressedBytes: _buildFakeArchive(modelName),
        targetDir: target,
        modelName: modelName,
        requiredFiles: const ['encoder_model.ort', 'missing_file.ort'],
      );

      expect(ok, isFalse);
      dir.deleteSync(recursive: true);
    });

    test('يستبدل المحتوى الموجود مسبقًا في المجلد الهدف', () async {
      const modelName = 'test-model-ar';
      final dir = Directory.systemTemp.createTempSync('wizano_extract');
      final target = '${dir.path}/$modelName';
      Directory(target).createSync(recursive: true);
      File('$target/stale.txt').writeAsStringSync('old');

      await extractModelArchive(
        compressedBytes: _buildFakeArchive(modelName),
        targetDir: target,
        modelName: modelName,
        requiredFiles: modelRequiredFiles,
      );

      expect(File('$target/stale.txt').existsSync(), isFalse);
      expect(File('$target/encoder_model.ort').existsSync(), isTrue);

      dir.deleteSync(recursive: true);
    });
  });
}

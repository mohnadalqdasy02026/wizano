import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shop_app/features/speech/speech_engine.dart';
import 'package:shop_app/services/speech/model_extractor.dart';
import 'package:shop_app/services/speech/model_manager.dart';

void main() {
  group('ModelManager', () {
    test('ينشئ مجلد النماذج قبل محاولة التنزيل (تثبيت جديد)', () async {
      final base = Directory.systemTemp.createTempSync('wizano_models');
      addTearDown(() {
        if (base.existsSync()) base.deleteSync(recursive: true);
      });

      final manager = ModelManager(
        baseDirProvider: () async => base,
        // رابط غير صالح: فشل سريع بلا تنزيل 119MB.
        modelUrl: 'http://127.0.0.1:1/model.tar.bz2',
      );

      // التنزيل نفسه سيفشل (لا شبكة في الاختبار)، لكن المهم أن المجلد
      // يُنشأ قبله — وهذا ما كان ينقص فتظهر استثناء على التثبيت الجديد.
      await expectLater(manager.ensureReady(), throwsA(anything));

      expect(Directory('${base.path}/models').existsSync(), isTrue);
      expect(manager.info.status, ModelStatus.error);
    });

    test('مسار النموذج داخل مجلد models', () async {
      final base = Directory.systemTemp.createTempSync('wizano_models');
      addTearDown(() {
        if (base.existsSync()) base.deleteSync(recursive: true);
      });

      final manager = ModelManager(baseDirProvider: () async => base);
      final dir = await manager.getModelDir();

      expect(dir, '${base.path}/models/${ModelManager.modelName}');
    });

    test('checkReady يفحص فقط ولا يبدأ تنزيلًا', () async {
      final base = Directory.systemTemp.createTempSync('wizano_models');
      addTearDown(() {
        if (base.existsSync()) base.deleteSync(recursive: true);
      });

      final manager = ModelManager(
        baseDirProvider: () async => base,
        modelUrl: 'http://127.0.0.1:1/model.tar.bz2',
      );

      await manager.checkReady();

      expect(manager.info.status, ModelStatus.notDownloaded);
      expect(
        Directory('${base.path}/models/${ModelManager.modelName}').existsSync(),
        isFalse,
      );
    });

    test('يستخدم النموذج العربي القديم المكتمل بدل تنزيل جديد', () async {
      final base = Directory.systemTemp.createTempSync('wizano_models');
      addTearDown(() {
        if (base.existsSync()) base.deleteSync(recursive: true);
      });

      final legacyDir = Directory('${base.path}/models/$legacyModelName');
      legacyDir.createSync(recursive: true);
      for (final name in legacyModelRequiredFiles) {
        File('${legacyDir.path}/$name').writeAsStringSync('x');
      }

      final manager = ModelManager(
        baseDirProvider: () async => base,
        // يجب ألا يُستدعى الشبكة إطلاقًا ما دام النموذج القديم مكتملًا.
        modelUrl: 'http://127.0.0.1:1/model.tar.bz2',
      );

      await manager.ensureReady();

      expect(manager.info.status, ModelStatus.ready);
      expect(manager.info.modelDir, legacyDir.path);

      await manager.deleteModel();
      expect(legacyDir.existsSync(), isFalse);
    });
  });
}


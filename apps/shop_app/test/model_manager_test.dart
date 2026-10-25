import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shop_app/features/speech/speech_engine.dart';
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
  });
}


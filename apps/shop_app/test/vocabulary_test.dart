import 'package:flutter_test/flutter_test.dart';
import 'package:shop_app/services/speech/vocabulary.dart';

void main() {
  group('Vocabulary.extractTerms', () {
    test('يستخرج الكلمات من نصّ أصناف ويتجاهل وحدات القياس', () {
      final terms = Vocabulary.extractTerms('كيلو رز، كيلو سكر، 2 علبة حليب');
      expect(terms, contains('رز'));
      expect(terms, contains('سكر'));
      expect(terms, contains('حليب'));
      expect(terms, isNot(contains('كيلو')));
      expect(terms, isNot(contains('علبة')));
    });

    test('يتجاهل الأرقام فقط', () {
      final terms = Vocabulary.extractTerms('12 34');
      expect(terms, isEmpty);
    });

    test('يزيل التشكيل من الكلمات المستخرجة', () {
      final terms = Vocabulary.extractTerms('كِيلُو سُكَّرَ');
      expect(terms, contains('سكر'));
      expect(terms, isNot(contains('كِيلُو')));
    });
  });

  group('Vocabulary.correct', () {
    test('يصحّح كلمة قريبة جدًا من مفردة معروفة', () {
      final terms = Vocabulary.build(shopTerms: const ['روز', 'سكر']);
      expect(Vocabulary.correct('كيلو روز', terms), 'كيلو روز');
      expect(Vocabulary.correct('كيلو سكر', terms), 'كيلو سكر');
    });

    test('يترك الكلمة الصحيحة كما هي', () {
      final terms = Vocabulary.build(shopTerms: const ['حليب']);
      expect(Vocabulary.correct('حليب كامل الدسم', terms), 'حليب كامل الدسم');
    });

    test('لا يغيّر الكلمات البعيدة عن المفردات', () {
      final terms = Vocabulary.build(shopTerms: const ['حليب']);
      expect(Vocabulary.correct('برتقال', terms), 'برتقال');
    });

    test('يعيد النص كما هو عند فراغ المفردات', () {
      expect(Vocabulary.correct('نص ما فيه تصحيح', const []), 'نص ما فيه تصحيح');
    });
  });

  group('Vocabulary.build', () {
    test('يدمج المفردات المدمجة مع أصناف المحل', () {
      final terms = Vocabulary.build(shopTerms: const ['منتج خاص']);
      expect(terms, contains('سكر'));
      expect(terms, contains('منتج خاص'));
    });
  });
}


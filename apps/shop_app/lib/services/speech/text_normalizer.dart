/// تنقية النص العربي الناتج عن التعرّف على الكلام.
///
/// المحرّك (moonshine-base-ar) يُخرِج نصًا **مشكولًا بالكامل** (حركات وعلامات)
/// وهو غير عملي للإدخال في خانة تفاصيل الأصناف؛ فهذه الدالة تُزيل التشكيل
/// والعلامات وتوحّد الأرقام والمسافات.
library;

/// محارف التشكيل والعلامات العربية (نطاقات Unicode).
const List<List<int>> _diacriticsRanges = [
  [0x0610, 0x061A], // علامات إسلامية / قرآنية
  [0x064B, 0x065F], // التشكيل: فتحتان..سكون
  [0x0670, 0x0670], // ألف خنجرية
  [0x06D6, 0x06ED], // علامات قرآنية
  [0x08D3, 0x08FF], // علامات عربية ممتدة
];

const int _tatweel = 0x0640; // ـ التطويل

bool _isDiacritic(int code) {
  for (final range in _diacriticsRanges) {
    if (code >= range[0] && code <= range[1]) return true;
  }
  return false;
}

/// الأرقام العربية-الهندية (٠..٩) والفارسية (۰..۹) → أرقام لاتينية.
String _toLatinDigits(String input) {
  const arabicIndic = '٠١٢٣٤٥٦٧٨٩';
  const extendedArabicIndic = '۰۱۲۳۴۵۶۷۸۹';
  final buffer = StringBuffer();
  for (final rune in input.runes) {
    final ch = String.fromCharCode(rune);
    final idx = arabicIndic.indexOf(ch);
    if (idx >= 0) {
      buffer.write(idx);
      continue;
    }
    final idx2 = extendedArabicIndic.indexOf(ch);
    if (idx2 >= 0) {
      buffer.write(idx2);
      continue;
    }
    buffer.write(ch);
  }
  return buffer.toString();
}

/// ينقّي نصًا عربيًا: يزيل التشكيل والتطويل، ويوحّد الأرقام والمسافات.
String normalizeArabicText(String input) {
  if (input.trim().isEmpty) return '';
  final buffer = StringBuffer();
  for (final rune in input.runes) {
    if (rune == _tatweel) continue;
    if (_isDiacritic(rune)) continue;
    buffer.writeCharCode(rune);
  }
  var result = _toLatinDigits(buffer.toString());
  result = result.replaceAll(RegExp(r'[ \t ]+'), ' ');
  result = result.replaceAll(RegExp(r' *\n *'), '\n');
  result = result.replaceAll(RegExp(r'\n{2,}'), '\n');
  return result.trim();
}

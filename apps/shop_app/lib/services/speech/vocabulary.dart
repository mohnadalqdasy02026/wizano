

/// مفردات تصحيح النص العربي المستخرج من الكلام، تعمل **دون إنترنت**.
///
/// مصدران:
/// 1. **قاموس أصناف شائع** مدمج في التطبيق (بضاعة بقالة).
/// 2. **أصناف المحل نفسه**: ما سجّله المحل سابقًا — فيتعلّم مفرداته تلقائيًا.
///
/// التصحيح يتم **بعد** التعرّف: تصحيح الكلمات القريبة من المفردات بمسافة تحرير
/// (Levenshtein).
///
/// **لماذا بعد التعرّف وليس قبله؟** خاصية `hotwords` في sherpa-onnx تتوقّف عن
/// العمل مع هذا النموذج: مفرداته على مستوى **البايت** (رموز مثل `PHVuaz4=`)،
/// فتمرير كلمات كاملة يجعل إنشاء المحرّك يفشل بالكامل
/// («Failed to create offline recognizer») ويتوقف التعرّف كليًّا.
class Vocabulary {
  /// أصناف بقالة شائعة تُبنى عليها المفردات.
  static const List<String> builtInTerms = [
    'رز', 'أرز', 'سكر', 'سكّر', 'ملح', 'زيت', 'زيت زيتون', 'حليب',
    'لبن', 'لبن زبادي', 'زبادي', 'دقيق', 'طحين', 'شاي', 'شاي أحمر', 'بن',
    'قهوة', 'بيض', 'بيض بلدي', 'لحم', 'لحم بقر', 'دجاج', 'سمك', 'تونة',
    'معجون', 'معجون طماطم', 'صلصة', 'صلصة طماطم', 'مخلل', 'عسل', 'مربى',
    'بسكويت', 'شوكولاتة', 'حلاوة', 'مكسرات', 'فول', 'عدس', 'حمص', 'كبسة',
    'أرز بسمتي', 'ماء', 'مشروب', 'عصير', 'مشروب غازي', 'معلب', 'تونة معلبة',
    'جبن', 'جبنة', 'لبن رائب', 'زبدة', 'كربونات', 'خميرة', 'vanilla', 'فانيليا',
    'تمر', 'عجينة', 'بسكويت سادة', 'حليب كامل الدسم', 'زبدة فول سوداني',
    'فول مدمس', 'حمص مغلي', 'كبسة عدس', 'شوربة', 'مقبلات', 'شربت',
  ];

  /// كلمات تُتجاهل عند استخراج المفردات من نصّ الأصناف.
  static const Set<String> _stopWords = {
    'كيلو', 'كليو', 'جم', 'علبة', 'حبة', 'كيس', 'شيكارة', 'باكيت',
    'قطعة', 'عدد', 'لتر', 'زجاجة', 'كوب', 'صحن', 'مقطوعة', 'قطع',
    'من', 'في', 'على', 'الى', 'عن', 'مع', 'و', 'او', 'ثم', 'هذا',
    'هذه', 'ذلك', 'كان', 'يكون', 'ال', 'كل', 'بعض', 'قدر', 'نص', 'نصف',
    'الكيس', 'الحبة', 'العلبة', 'بارز', 'تقريبا', 'حوالي',
  };

  /// يستخرج الكلمات المرشّحة من نصّ تفاصيل الأصناف.
  static List<String> extractTerms(String itemsText) {
    final out = <String>{};
    for (final raw in itemsText.split(RegExp(r'[\n،,.;:؟?!()\[\]"]+'))) {
      final chunk = raw.trim();
      if (chunk.isEmpty) continue;
      for (final word in chunk.split(RegExp(r'\s+'))) {
        final w = _stripDiacritics(word).replaceAll(RegExp(r"['’]"), '');
        if (w.length < 2) continue;
        if (_stopWords.contains(w)) continue;
        if (w.contains(RegExp(r'^\d+$'))) continue;
        out.add(w);
      }
    }
    return out.toList();
  }

  /// يزيل التشكيل ليعمل المقارنة على أساس نصّي واحد.
  static String _stripDiacritics(String input) {
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      if (rune >= 0x064B && rune <= 0x065F) continue;
      if (rune == 0x0640) continue;
      if (rune >= 0x0610 && rune <= 0x061A) continue;
      if (rune >= 0x06D6 && rune <= 0x06ED) continue;
      buffer.writeCharCode(rune);
    }
    return buffer.toString();
  }

  /// يبني قائمة المفردات النهائية (المدمجة + أصناف المحل).
  static List<String> build({Iterable<String> shopTerms = const []}) {
    final out = <String>{};
    for (final t in builtInTerms) {
      out.add(_stripDiacritics(t));
    }
    for (final t in shopTerms) {
      final clean = _stripDiacritics(t.trim());
      if (clean.length >= 2) out.add(clean);
    }
    return out.toList();
  }

  /// تصحيح نصّي تقريبي: يستبدل كل كلمة قريبة جدًا من مفردة معروفة.
  ///
  /// - لا يُغيّر الكلمة إن كانت مطابقة أو قريبة جدًا.
  /// - الحد الأقصى للمسافة = 1 للكلمات القصيرة (≤4) و2 للأطول.
  static String correct(String text, List<String> terms) {
    if (text.trim().isEmpty || terms.isEmpty) return text;
    final lookup = <String, String>{};
    for (final t in terms) {
      lookup[_stripDiacritics(t).toLowerCase()] = t;
    }
    return text
        .split('\n')
        .map((line) => _correctLine(line, lookup))
        .join('\n');
  }

  static String _correctLine(String line, Map<String, String> lookup) {
    final words =
        line.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return line;
    return words.map((w) => _correctWord(w, lookup)).join(' ');
  }

  static String _correctWord(String token, Map<String, String> lookup) {
    final clean = _stripDiacritics(token).toLowerCase();
    if (lookup.containsKey(clean)) return token;
    final maxDistance = clean.length <= 4 ? 1 : 2;
    String? best;
    int bestDistance = maxDistance + 1;
    for (final entry in lookup.entries) {
      final candidate = entry.key;
      if ((candidate.length - clean.length).abs() > maxDistance) continue;
      final d = _levenshtein(clean, candidate);
      if (d < bestDistance) {
        bestDistance = d;
        best = entry.value;
      }
    }
    if (best == null) return token;
    if (token == token.toUpperCase() && token.length > 1) return best.toUpperCase();
    return best;
  }

  static int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    var previous = List<int>.generate(b.length + 1, (i) => i);
    var current = List<int>.filled(b.length + 1, 0);
    for (var i = 1; i <= a.length; i++) {
      current[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        final deletion = current[j - 1] + 1;
        final insertion = previous[j] + 1;
        final substitution = previous[j - 1] + cost;
        var value = deletion;
        if (insertion < value) value = insertion;
        if (substitution < value) value = substitution;
        current[j] = value;
      }
      final swap = previous;
      previous = current;
      current = swap;
    }
    return previous[b.length];
  }
}


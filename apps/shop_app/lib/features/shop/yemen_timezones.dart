/// خيارات المنطقة الزمنية المعروضة في التطبيق.
///
/// اليمن كلها في منطقة زمنية واحدة (UTC+3)، لكن صاحب المحل يتعرّف على محافظته
/// لا على معرّف IANA الإنجليزي مثل `Asia/Aden`. لذلك نعرض أسماء المحافظات
/// بالعربية، ونحفظ الاسم المختار نفسه في حقل المنطقة الزمنية (قيمة عرضية لا
/// تدخل في أي حساب مالي).
class TimezoneOption {
  const TimezoneOption(this.label, this.value);

  /// النص العربي الظاهر للمستخدم.
  final String label;

  /// القيمة المحفوظة على الخادم.
  final String value;
}

/// محافظات اليمن (22 محافظة + أمانة العاصمة) ثم مناطق خارج اليمن.
const List<TimezoneOption> timezoneOptions = [
  TimezoneOption('أمانة العاصمة', 'أمانة العاصمة'),
  TimezoneOption('صنعاء', 'صنعاء'),
  TimezoneOption('عدن', 'عدن'),
  TimezoneOption('تعز', 'تعز'),
  TimezoneOption('الحديدة', 'الحديدة'),
  TimezoneOption('إب', 'إب'),
  TimezoneOption('ذمار', 'ذمار'),
  TimezoneOption('حجة', 'حجة'),
  TimezoneOption('عمران', 'عمران'),
  TimezoneOption('صعدة', 'صعدة'),
  TimezoneOption('المحويت', 'المحويت'),
  TimezoneOption('ريمة', 'ريمة'),
  TimezoneOption('البيضاء', 'البيضاء'),
  TimezoneOption('مأرب', 'مأرب'),
  TimezoneOption('الجوف', 'الجوف'),
  TimezoneOption('شبوة', 'شبوة'),
  TimezoneOption('أبين', 'أبين'),
  TimezoneOption('لحج', 'لحج'),
  TimezoneOption('الضالع', 'الضالع'),
  TimezoneOption('المهرة', 'المهرة'),
  TimezoneOption('حضرموت', 'حضرموت'),
  TimezoneOption('سقطرى', 'سقطرى'),
  TimezoneOption('السعودية — الرياض', 'Asia/Riyadh'),
  TimezoneOption('الإمارات — دبي', 'Asia/Dubai'),
  TimezoneOption('التوقيت العالمي UTC', 'UTC'),
];

/// القيمة الافتراضية لمحل جديد.
const String defaultTimezone = 'صنعاء';

/// يعرض قيمة المنطقة الزمنية المخزّنة بالعربية، بما فيها القيم القديمة
/// بصيغة IANA (محلات أُنشئت قبل هذا التغيير).
String timezoneLabel(String? value) {
  if (value == null || value.trim().isEmpty) return '—';
  switch (value) {
    case 'Asia/Aden':
      return 'عدن';
    case 'Asia/Riyadh':
      return 'السعودية — الرياض';
    case 'Asia/Dubai':
      return 'الإمارات — دبي';
    case 'UTC':
      return 'التوقيت العالمي UTC';
    default:
      return value;
  }
}

/// قيمة صالحة للقائمة المنسدلة انطلاقًا من القيمة المخزّنة.
String timezoneOptionValue(String? value) {
  if (value == null) return defaultTimezone;
  if (timezoneOptions.any((option) => option.value == value)) return value;
  if (value == 'Asia/Aden') return 'عدن';
  return defaultTimezone;
}

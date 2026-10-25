/// بديل محلي لحزمة `sherpa_onnx_web` الرسمية.
///
/// حزمة `sherpa_onnx` تستورد هذه الحزمة بشرط (conditional import) ليعمل محرك
/// WASM على المتصفّح فقط؛ وعلى أندرويد يستخدم بديلًا داخليًا بلا ملفات.
/// إن留下的 ملف WASM (‏14.4 ميجابايت) كان يُضمَّن في حزمة أندرويد بلا فائدة،
/// لذلك نستبدل الحزمة بهذه النسخة الخفيفة التي لا تحمل أي أصول.
class SherpaOnnxWeb {
  const SherpaOnnxWeb._();

  static Future<void> loadWasm() async {}
}

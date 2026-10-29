import 'package:flutter/material.dart';

/// دليل مبسط داخل التطبيق، متاح دون اتصال بالإنترنت.
class HowToUseScreen extends StatelessWidget {
  const HowToUseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('طريقة الاستخدام')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          _Intro(),
          SizedBox(height: 12),
          _GuideStep(number: '١', icon: Icons.person_add_alt_1_outlined, title: 'أضف العميل', body: 'من قسم العملاء اختر إضافة عميل، ثم أدخل اسمه ورقم هاتفه إن وُجد. أنشئ رابط الدعوة وأرسله للعميل ليدخل تطبيقه.'),
          _GuideStep(number: '٢', icon: Icons.shopping_bag_outlined, title: 'سجّل شراءً أو دفعة', body: 'افتح صفحة العميل واختر إضافة عملية. سجّل المبلغ والوصف؛ سيُحدَّث رصيد العميل وكشف الحساب تلقائيًا.'),
          _GuideStep(number: '٣', icon: Icons.wifi_off_outlined, title: 'استخدم التطبيق دون إنترنت', body: 'يمكنك متابعة العمل عند انقطاع الشبكة. تُحفظ العمليات والرسائل على الهاتف وتُزامن تلقائيًا عند عودة الاتصال.'),
          _GuideStep(number: '٤', icon: Icons.picture_as_pdf_outlined, title: 'اطبع كشف الحساب', body: 'افتح صفحة العميل ثم كشف الحساب واضغط أيقونة PDF بالأعلى. يمكنك مشاركة الملف أو طباعته مباشرةً.'),
          _GuideStep(number: '٥', icon: Icons.chat_bubble_outline, title: 'راسل العميل', body: 'من قسم الرسائل اختر العميل واكتب رسالتك. تظهر علامة حمراء أسفل الرسالة التي تنتظر الإرسال عند عدم وجود إنترنت.'),
          _GuideStep(number: '٦', icon: Icons.mic_none_outlined, title: 'الإدخال بالصوت', body: 'من الإعدادات نزّل نموذج الصوت مرةً واحدة. بعد ذلك يمكنك استخدامه دون إنترنت عند تسجيل العمليات.'),
          _GuideStep(number: '٧', icon: Icons.security_outlined, title: 'حافظ على بياناتك', body: 'لا تشارك كلمة المرور أو جهازك مع الآخرين. أنشئ نسخة احتياطية دورية من قاعدة البيانات قبل أي تحديث كبير.'),
        ],
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro();

  @override
  Widget build(BuildContext context) => Card(
        color: const Color(0xFFEAF7F5),
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('مرحبًا بك في وزانو', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: Color(0xFF0B2A4A))),
            SizedBox(height: 6),
            Text('دليل سريع لإدارة العملاء والديون والمدفوعات بسهولة.'),
          ]),
        ),
      );
}

class _GuideStep extends StatelessWidget {
  const _GuideStep({required this.number, required this.icon, required this.title, required this.body});

  final String number;
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(backgroundColor: const Color(0xFF0B2A4A), child: Text(number, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Icon(icon, color: const Color(0xFF16A39A)), const SizedBox(width: 7), Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)))]),
              const SizedBox(height: 7),
              Text(body, style: const TextStyle(height: 1.45)),
            ])),
          ]),
        ),
      );
}

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

const _apiBase = String.fromEnvironment('API_BASE_URL');
const _storage = FlutterSecureStorage();

abstract final class CustomerColors {
  static const navy = Color(0xFF041B3A);
  static const navyBright = Color(0xFF073B78);
  static const teal = Color(0xFF14D7B0);
  static const blue = Color(0xFF0878F9);
  static const gold = Color(0xFFFFC94A);
  static const background = Color(0xFFF2F7FF);
}

void main() => runApp(const CustomerApp());

class CustomerApp extends StatelessWidget {
  const CustomerApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'WIZANO عميل',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: CustomerColors.background,
          colorScheme: ColorScheme.fromSeed(
            seedColor: CustomerColors.navy,
            primary: CustomerColors.navy,
            secondary: CustomerColors.teal,
            tertiary: CustomerColors.gold,
            surface: Colors.white,
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: CustomerColors.navy,
            foregroundColor: Colors.white,
            centerTitle: true,
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: CustomerColors.navy,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(54),
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: CustomerColors.navy.withValues(alpha: .10))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: CustomerColors.teal, width: 2)),
          ),
        ),
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
        builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
        home: const SessionGate(),
      );
}

bool get _apiConfigured {
  final uri = Uri.tryParse(_apiBase);
  return uri != null && uri.hasAuthority && (uri.scheme == 'https' || (kDebugMode && uri.scheme == 'http'));
}

class SessionGate extends StatelessWidget {
  const SessionGate({super.key});

  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
        future: _storage.read(key: 'wizano.customer.access'),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          final token = snapshot.data;
          return token == null ? const LoginScreen() : HomeScreen(token: token);
        },
      );
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _invitationCode = TextEditingController();
  String? _error;
  bool _loading = false;

  @override
  void dispose() { _invitationCode.dispose(); super.dispose(); }

  Future<void> _login() async {
    if (!_apiConfigured) { setState(() => _error = 'استخدم API_BASE_URL بعنوان HTTPS.'); return; }
    setState(() { _loading = true; _error = null; });
    try {
      final code = _invitationCodeFrom(_invitationCode.text);
      if (code.isEmpty) { setState(() => _error = 'أدخل رمز أو رابط الدعوة.'); return; }
      final response = await http.post(Uri.parse('$_apiBase/api/v1/customer-invitations/access'), headers: const {'content-type': 'application/json'}, body: jsonEncode({'code': code})).timeout(const Duration(seconds: 12));
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final tokens = payload['data']?['tokens'] as Map<String, dynamic>?;
      final access = tokens?['accessToken'] as String?;
      final refresh = tokens?['refreshToken'] as String?;
      if (response.statusCode != 200 || access == null || refresh == null) {
        final serverMessage = (payload['error'] as Map<String, dynamic>?)?['message_ar']?.toString();
        setState(() => _error = serverMessage ?? 'تعذر التحقق من رابط الدعوة (رمز الحالة: ${response.statusCode}).');
        return;
      }
      await _storage.write(key: 'wizano.customer.access', value: access);
      await _storage.write(key: 'wizano.customer.refresh', value: refresh);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => HomeScreen(token: access)));
    } catch (_) {
      setState(() => _error = 'تعذر الوصول إلى الخادم.');
    } finally { if (mounted) setState(() => _loading = false); }
  }

  String _invitationCodeFrom(String raw) {
    final text = raw.trim();
    final uri = Uri.tryParse(text);
    final fromUrl = uri?.queryParameters['code'];
    return (fromUrl ?? text).trim().toUpperCase();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: SingleChildScrollView(child: Column(children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 22),
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [CustomerColors.navy, CustomerColors.navyBright], begin: Alignment.topRight, end: Alignment.bottomLeft),
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(34)),
        ),
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Image.asset('assets/images/app_icon.png', width: 42, height: 42),
            const SizedBox(width: 10),
            const Text('WIZANO', textDirection: TextDirection.ltr, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 23, letterSpacing: 1.2)),
          ]),
          const SizedBox(height: 10),
          const Text('متابعة حسابك بكل وضوح وأمان', style: TextStyle(color: Color(0xFFD9E8FF), fontWeight: FontWeight.w600)),
        ]),
      ),
      Padding(padding: const EdgeInsets.fromLTRB(22, 12, 22, 28), child: Column(children: [
        Image.asset('assets/images/customer_login_hero.png', height: 220, fit: BoxFit.contain, filterQuality: FilterQuality.high),
        const Align(alignment: Alignment.centerRight, child: Text('أهلًا بك', style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900, color: CustomerColors.navy))),
        const SizedBox(height: 7),
        const Text('الصق رمز الدعوة أو الرابط الذي أرسله لك صاحب المحل لعرض كشف حسابك.', style: TextStyle(color: Color(0xFF60738C), height: 1.6), textAlign: TextAlign.right),
        const SizedBox(height: 20),
        TextField(controller: _invitationCode, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'رمز أو رابط الدعوة', prefixIcon: Icon(Icons.link_rounded, color: CustomerColors.teal))),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: _MessageBox(message: _error!)),
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, child: ElevatedButton.icon(onPressed: _loading ? null : _login, icon: _loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.verified_user_rounded), label: Text(_loading ? 'جارٍ التحقق...' : 'فتح حسابي'))),
        const SizedBox(height: 16),
        const Row(children: [Expanded(child: Divider()), Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Icon(Icons.lock_outline_rounded, size: 17, color: CustomerColors.teal)), Expanded(child: Divider())]),
        const SizedBox(height: 9),
        const Text('لا تحتاج إلى بريد إلكتروني أو كلمة مرور', style: TextStyle(color: Color(0xFF718096), fontSize: 12, fontWeight: FontWeight.w600)),
      ])),
    ])),
  );
}

class _MessageBox extends StatelessWidget {
  const _MessageBox({required this.message});
  final String message;
  @override Widget build(BuildContext context) => Container(
    width: double.infinity, padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: const Color(0xFFFFEEF0), borderRadius: BorderRadius.circular(14)),
    child: Row(children: [const Icon(Icons.info_outline_rounded, color: Color(0xFFD9435E)), const SizedBox(width: 8), Expanded(child: Text(message, style: const TextStyle(color: Color(0xFFB4233B), fontWeight: FontWeight.w600)))]),
  );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.token});
  final String token;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<dynamic> _shops = const [];
  String? _error;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try {
      final response = await http.get(Uri.parse('$_apiBase/api/v1/shops'), headers: {'authorization': 'Bearer ${widget.token}'}).timeout(const Duration(seconds: 12));
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200) throw const FormatException();
      setState(() => _shops = (payload['data']?['items'] as List?) ?? const []);
    } catch (_) { setState(() => _error = 'تعذر جلب المحلات المرتبطة بحسابك.'); }
  }
  Future<void> _logout() async { await _storage.deleteAll(); if (mounted) Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false); }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('محلاتي'), actions: [IconButton(onPressed: _logout, icon: const Icon(Icons.logout_rounded))]), body: _error != null ? Center(child: Text(_error!)) : _shops.isEmpty ? const Center(child: Text('لا يوجد محل مرتبط. اطلب رمز دعوة من صاحب المحل.')) : ListView(padding: const EdgeInsets.all(18), children: [const Text('اختر المحل لعرض كشف حسابك', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600)), const SizedBox(height: 14), ..._shops.map((shop) => Card(elevation: 0, clipBehavior: Clip.antiAlias, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), child: InkWell(onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => StatementScreen(token: widget.token, shopId: shop['id'] as String, shopName: shop['name']?.toString() ?? ''))), child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: CustomerColors.teal.withValues(alpha: .14), borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.storefront_rounded, color: CustomerColors.navy)), const SizedBox(width: 13), Expanded(child: Text(shop['name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17))), const Icon(Icons.chevron_left_rounded, color: CustomerColors.navyBright)]))))]));
}

class StatementScreen extends StatefulWidget {
  const StatementScreen({super.key, required this.token, required this.shopId, required this.shopName});
  final String token; final String shopId; final String shopName;
  @override
  State<StatementScreen> createState() => _StatementScreenState();
}

class _StatementScreenState extends State<StatementScreen> {
  Map<String, dynamic>? _statement;
  String? _error;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try {
      final response = await http.get(Uri.parse('$_apiBase/api/v1/shops/${widget.shopId}/my-statement'), headers: {'authorization': 'Bearer ${widget.token}'}).timeout(const Duration(seconds: 12));
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200) throw const FormatException();
      setState(() => _statement = payload['data'] as Map<String, dynamic>);
    } catch (_) { setState(() => _error = 'تعذر جلب كشف الحساب.'); }
  }
  @override
  Widget build(BuildContext context) {
    if (_error != null) return Scaffold(appBar: AppBar(title: Text(widget.shopName)), body: Center(child: Text(_error!)));
    final statement = _statement;
    if (statement == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final entries = statement['entries'] as List<dynamic>? ?? const [];
    return Scaffold(appBar: AppBar(title: Text(widget.shopName)), body: Column(children: [
      Container(width: double.infinity, margin: const EdgeInsets.fromLTRB(16, 16, 16, 12), padding: const EdgeInsets.all(20), decoration: BoxDecoration(gradient: const LinearGradient(colors: [CustomerColors.navy, CustomerColors.navyBright]), borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: CustomerColors.navy.withValues(alpha: .2), blurRadius: 20, offset: const Offset(0, 8))]), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('الرصيد المتبقي', style: TextStyle(color: Color(0xFFBBD7FF), fontWeight: FontWeight.w600)), const SizedBox(height: 7), Text('${statement['balance']} ر.ي', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 29)), const SizedBox(height: 8), const Row(children: [Icon(Icons.verified_rounded, color: CustomerColors.teal, size: 18), SizedBox(width: 6), Text('كشف حساب محدّث من المحل', style: TextStyle(color: Colors.white70, fontSize: 12))])])),
      const Padding(padding: EdgeInsets.fromLTRB(20, 8, 20, 6), child: Align(alignment: Alignment.centerRight, child: Text('سجل العمليات', style: TextStyle(fontWeight: FontWeight.w900, color: CustomerColors.navy, fontSize: 17))),),
      Expanded(child: entries.isEmpty ? const Center(child: Text('لا توجد عمليات مسجلة حتى الآن')) : ListView.separated(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), itemCount: entries.length, separatorBuilder: (_, __) => const SizedBox(height: 9), itemBuilder: (_, i) { final entry = entries[i] as Map<String, dynamic>; final effect = entry['effect']?.toString() ?? ''; final positive = effect.contains('payment') || effect.contains('credit'); return Card(elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)), child: ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7), leading: Container(padding: const EdgeInsets.all(9), decoration: BoxDecoration(color: (positive ? CustomerColors.teal : CustomerColors.gold).withValues(alpha: .15), borderRadius: BorderRadius.circular(13)), child: Icon(positive ? Icons.south_west_rounded : Icons.receipt_long_rounded, color: positive ? CustomerColors.teal : const Color(0xFFB7791F))), title: Text(entry['description']?.toString() ?? entry['type']?.toString() ?? 'عملية', style: const TextStyle(fontWeight: FontWeight.w800)), subtitle: Text(entry['occurredAt']?.toString().split('T').first ?? ''), trailing: Text(effect, style: TextStyle(fontWeight: FontWeight.w800, color: positive ? CustomerColors.teal : CustomerColors.navy))); }))
    ]));
  }
}

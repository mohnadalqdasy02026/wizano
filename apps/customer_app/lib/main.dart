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
              minimumSize: const Size(200, 48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
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
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _invitationCode = TextEditingController();
  String? _error;
  bool _loading = false;

  @override
  void dispose() { _email.dispose(); _password.dispose(); _invitationCode.dispose(); super.dispose(); }

  Future<void> _login() async {
    if (!_apiConfigured) { setState(() => _error = 'استخدم API_BASE_URL بعنوان HTTPS.'); return; }
    setState(() { _loading = true; _error = null; });
    try {
      final response = await http.post(Uri.parse('$_apiBase/api/v1/auth/login'), headers: const {'content-type': 'application/json'}, body: jsonEncode({'email': _email.text.trim(), 'password': _password.text})).timeout(const Duration(seconds: 12));
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final tokens = payload['data']?['tokens'] as Map<String, dynamic>?;
      final access = tokens?['accessToken'] as String?;
      final refresh = tokens?['refreshToken'] as String?;
      if (response.statusCode != 200 || access == null || refresh == null) { setState(() => _error = 'بيانات الدخول غير صحيحة.'); return; }
      final invitationCode = _invitationCode.text.trim();
      if (invitationCode.isNotEmpty) {
        final invitationResponse = await http.post(
          Uri.parse('$_apiBase/api/v1/customer-invitations/accept'),
          headers: {'content-type': 'application/json', 'authorization': 'Bearer $access'},
          body: jsonEncode({'code': invitationCode}),
        ).timeout(const Duration(seconds: 12));
        if (invitationResponse.statusCode != 200) {
          setState(() => _error = 'رمز الدعوة غير صالح أو منتهي.');
          return;
        }
      }
      await _storage.write(key: 'wizano.customer.access', value: access);
      await _storage.write(key: 'wizano.customer.refresh', value: refresh);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => HomeScreen(token: access)));
    } catch (_) {
      setState(() => _error = 'تعذر الوصول إلى الخادم.');
    } finally { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('WIZANO — عميل')), body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(children: [
    Image.asset('assets/images/customer_login_hero.png', height: 210, fit: BoxFit.contain, filterQuality: FilterQuality.high),
    const SizedBox(height: 8),
    const Text('حسابك واضح، وحقك محفوظ.', style: TextStyle(color: CustomerColors.navyBright, fontWeight: FontWeight.w800, fontSize: 18)),
    const SizedBox(height: 20),
    TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'البريد الإلكتروني')),
    TextField(controller: _password, obscureText: true, decoration: const InputDecoration(labelText: 'كلمة المرور')),
    TextField(controller: _invitationCode, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'رمز الدعوة (عند الربط الأول فقط)')),
    const SizedBox(height: 12), if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
    ElevatedButton(onPressed: _loading ? null : _login, child: Text(_loading ? 'جارٍ الدخول...' : 'دخول')),
  ])));
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
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('محلاتي'), actions: [IconButton(onPressed: _logout, icon: const Icon(Icons.logout))]), body: _error != null ? Center(child: Text(_error!)) : _shops.isEmpty ? const Center(child: Text('لا يوجد محل مرتبط. اطلب رمز دعوة من صاحب المحل.')) : ListView(children: _shops.map((shop) => ListTile(title: Text(shop['name']?.toString() ?? ''), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => StatementScreen(token: widget.token, shopId: shop['id'] as String, shopName: shop['name']?.toString() ?? ''))))).toList()));
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
    return Scaffold(appBar: AppBar(title: Text('كشف حساب — ${widget.shopName}')), body: Column(children: [
      Padding(padding: const EdgeInsets.all(16), child: Text('المتبقي: ${statement['balance']} ر.ي', style: Theme.of(context).textTheme.titleLarge)),
      Expanded(child: ListView(children: entries.map((entry) => ListTile(title: Text(entry['description']?.toString() ?? entry['type']?.toString() ?? ''), subtitle: Text(entry['occurredAt']?.toString() ?? ''), trailing: Text(entry['effect']?.toString() ?? ''))).toList())),
    ]));
  }
}

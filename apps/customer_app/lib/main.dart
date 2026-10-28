import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

const _apiBase = String.fromEnvironment('API_BASE_URL');
const _storage = FlutterSecureStorage();
const _shopsCacheKey = 'wizano.customer.cache.shops';

String _statementCacheKey(String shopId) =>
    'wizano.customer.cache.statement.$shopId';
String _messagesCacheKey(String shopId) =>
    'wizano.customer.cache.messages.$shopId';

Future<void> _saveCache(String key, Object value) =>
    _storage.write(key: key, value: jsonEncode(value));

Future<Map<String, dynamic>?> _readMapCache(String key) async {
  final raw = await _storage.read(key: key);
  if (raw == null) return null;
  try {
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (_) {
    return null;
  }
}

Future<List<dynamic>?> _readListCache(String key) async {
  final raw = await _storage.read(key: key);
  if (raw == null) return null;
  try {
    final decoded = jsonDecode(raw);
    return decoded is List<dynamic> ? decoded : null;
  } catch (_) {
    return null;
  }
}

abstract final class CustomerColors {
  static const navy = Color(0xFF041B3A);
  static const navyBright = Color(0xFF073B78);
  static const teal = Color(0xFF14D7B0);
  static const blue = Color(0xFF0878F9);
  static const gold = Color(0xFFFFC94A);
  static const background = Color(0xFFF2F7FF);
}

class OfflineNotice extends StatelessWidget {
  const OfflineNotice({super.key, required this.visible});
  final bool visible;

  @override
  Widget build(BuildContext context) => AnimatedSize(
        duration: const Duration(milliseconds: 220),
        child: visible
            ? Container(
                width: double.infinity,
                color: const Color(0xFF34495E),
                padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 16),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.cloud_off_rounded, color: Colors.white, size: 17),
                    SizedBox(width: 7),
                    Text(
                      'غير متصل — يتم عرض آخر بيانات محفوظة',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              )
            : const SizedBox.shrink(),
      );
}

class OfflineEmptyPanel extends StatelessWidget {
  const OfflineEmptyPanel({super.key, required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('assets/images/offline_sync.png', height: 170),
              const SizedBox(height: 16),
              const Text(
                'أنت غير متصل بالإنترنت',
                style: TextStyle(
                  color: CustomerColors.navy,
                  fontWeight: FontWeight.w900,
                  fontSize: 21,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'ستظهر آخر بياناتك المحفوظة تلقائيًا عند توفرها، وسيحاول التطبيق الاتصال فور عودة الشبكة.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF60738C), height: 1.55),
              ),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.wifi_find_rounded),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );

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
    ]))),
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

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  List<dynamic> _shops = const [];
  Timer? _poller;
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restoreCache();
    _load();
    _poller = Timer.periodic(const Duration(seconds: 8), (_) => _load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poller?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _restoreCache() async {
    final cached = await _readListCache(_shopsCacheKey);
    if (!mounted || cached == null) return;
    setState(() => _shops = cached);
  }

  Future<void> _load() async {
    try {
      final response = await http.get(Uri.parse('$_apiBase/api/v1/shops'), headers: {'authorization': 'Bearer ${widget.token}'}).timeout(const Duration(seconds: 12));
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200) throw const FormatException();
      final shops = (payload['data']?['items'] as List?) ?? const [];
      await _saveCache(_shopsCacheKey, shops);
      if (!mounted) return;
      setState(() {
        _shops = shops;
        _offline = false;
      });
    } catch (_) {
      if (mounted) setState(() => _offline = true);
    }
  }
  Future<void> _logout() async { await _storage.deleteAll(); if (mounted) Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false); }

  Future<void> _openAddShop() async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AddShopScreen(token: widget.token)),
    );
    if (added == true && mounted) await _load();
  }

  void _openStatement(Map<String, dynamic> shop) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StatementScreen(
          token: widget.token,
          shopId: shop['id'] as String,
          shopName: shop['name']?.toString() ?? '',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('محلاتي'),
      actions: [IconButton(onPressed: _logout, icon: const Icon(Icons.logout_rounded))],
    ),
    drawer: Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [CustomerColors.navy, CustomerColors.navyBright],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                ),
              ),
              child: Row(children: [
                Image.asset('assets/images/app_icon.png', width: 42, height: 42),
                const SizedBox(width: 12),
                const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('WIZANO', textDirection: TextDirection.ltr, style: TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w900, letterSpacing: 1)),
                  SizedBox(height: 3),
                  Text('حسابات المحلات', style: TextStyle(color: Color(0xFFD9E8FF), fontSize: 13)),
                ])),
              ]),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Text('محلاتي المرتبطة', style: TextStyle(color: CustomerColors.navy, fontWeight: FontWeight.w900)),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: _shops.map((item) {
                  final shop = item as Map<String, dynamic>;
                  return ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: CustomerColors.teal.withValues(alpha: .14), borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.storefront_rounded, color: CustomerColors.navy),
                    ),
                    title: Text(shop['name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text(shop['currency']?.toString() ?? ''),
                    trailing: const Icon(Icons.chevron_left_rounded),
                    onTap: () {
                      Navigator.pop(context);
                      _openStatement(shop);
                    },
                  );
                }).toList(),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: CustomerColors.gold.withValues(alpha: .18), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.add_business_rounded, color: CustomerColors.navy),
              ),
              title: const Text('إضافة محل جديد', style: TextStyle(fontWeight: FontWeight.w900)),
              subtitle: const Text('استخدم رمز دعوة من صاحب المحل'),
              onTap: () {
                Navigator.pop(context);
                _openAddShop();
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    ),
    body: Column(children: [
      OfflineNotice(visible: _offline),
      Expanded(
        child: _shops.isEmpty
            ? (_offline
                ? OfflineEmptyPanel(onRetry: _load)
                : const Center(child: CircularProgressIndicator()))
            : ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  const Text('اختر المحل لعرض كشف حسابك', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
                  const SizedBox(height: 14),
                  ..._shops.map((shop) => Card(
                    elevation: 0,
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    child: InkWell(
                      onTap: () => _openStatement(shop as Map<String, dynamic>),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(children: [
                          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: CustomerColors.teal.withValues(alpha: .14), borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.storefront_rounded, color: CustomerColors.navy)),
                          const SizedBox(width: 13),
                          Expanded(child: Text(shop['name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17))),
                          const Icon(Icons.chevron_left_rounded, color: CustomerColors.navyBright),
                        ]),
                      ),
                    ),
                  )),
                ],
              ),
      ),
    ]),
  );
}

class AddShopScreen extends StatefulWidget {
  const AddShopScreen({super.key, required this.token});

  final String token;

  @override
  State<AddShopScreen> createState() => _AddShopScreenState();
}

class _AddShopScreenState extends State<AddShopScreen> {
  final _invitationCode = TextEditingController();
  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _invitationCode.dispose();
    super.dispose();
  }

  Future<void> _addShop() async {
    final code = _codeFromInvitation(_invitationCode.text);
    if (code.isEmpty) {
      setState(() => _error = 'أدخل رمز أو رابط الدعوة.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await http
          .post(
            Uri.parse('$_apiBase/api/v1/customer-invitations/accept'),
            headers: {
              'content-type': 'application/json',
              'authorization': 'Bearer ${widget.token}',
            },
            body: jsonEncode({'code': code}),
          )
          .timeout(const Duration(seconds: 12));
      final payload = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode != 200) {
        final message = (payload['error'] as Map<String, dynamic>?)?['message_ar']?.toString();
        setState(() => _error = message ?? 'تعذر إضافة المحل (رمز الحالة: ${response.statusCode}).');
        return;
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      setState(() => _error = 'تعذر الوصول إلى الخادم.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _codeFromInvitation(String raw) {
    final text = raw.trim();
    final uri = Uri.tryParse(text);
    return (uri?.queryParameters['code'] ?? text).trim().toUpperCase();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('إضافة محل جديد')),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Image.asset('assets/images/customer_login_hero.png', height: 205, fit: BoxFit.contain),
            const SizedBox(height: 8),
            const Text('ربط محل إضافي', style: TextStyle(color: CustomerColors.navy, fontSize: 26, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            const Text('أدخل رمز الدعوة من صاحب المحل. سيُضاف المحل إلى حسابك الحالي، ولن تحتاج لإنشاء حساب جديد.', style: TextStyle(color: Color(0xFF60738C), height: 1.6)),
            const SizedBox(height: 22),
            TextField(
              controller: _invitationCode,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'رمز أو رابط الدعوة', prefixIcon: Icon(Icons.add_link_rounded, color: CustomerColors.teal)),
            ),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: _MessageBox(message: _error!)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loading ? null : _addShop,
              icon: _loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.storefront_rounded),
              label: Text(_loading ? 'جارٍ إضافة المحل...' : 'إضافة المحل إلى حسابي'),
            ),
          ],
        ),
      ),
    ),
  );
}

class StatementScreen extends StatefulWidget {
  const StatementScreen({super.key, required this.token, required this.shopId, required this.shopName});
  final String token; final String shopId; final String shopName;
  @override
  State<StatementScreen> createState() => _StatementScreenState();
}

class _StatementScreenState extends State<StatementScreen>
    with WidgetsBindingObserver {
  Map<String, dynamic>? _statement;
  Timer? _poller;
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restoreCache();
    _load();
    _poller = Timer.periodic(const Duration(seconds: 8), (_) => _load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poller?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _restoreCache() async {
    final cached = await _readMapCache(_statementCacheKey(widget.shopId));
    if (mounted && cached != null) setState(() => _statement = cached);
  }

  Future<void> _load() async {
    try {
      final response = await http.get(Uri.parse('$_apiBase/api/v1/shops/${widget.shopId}/my-statement'), headers: {'authorization': 'Bearer ${widget.token}'}).timeout(const Duration(seconds: 12));
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200) throw const FormatException();
      final statement = payload['data'] as Map<String, dynamic>;
      await _saveCache(_statementCacheKey(widget.shopId), statement);
      if (mounted) setState(() { _statement = statement; _offline = false; });
    } catch (_) {
      if (mounted) setState(() => _offline = true);
    }
  }
  void _openMessages() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => CustomerMessagesScreen(token: widget.token, shopId: widget.shopId, shopName: widget.shopName)));
  }
  @override
  Widget build(BuildContext context) {
    final statement = _statement;
    if (statement == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.shopName)),
        body: _offline
            ? OfflineEmptyPanel(onRetry: _load)
            : const Center(child: CircularProgressIndicator()),
      );
    }
    final entries = statement['entries'] as List<dynamic>? ?? const [];
    return Scaffold(
      appBar: AppBar(title: Text(widget.shopName), actions: [IconButton(tooltip: 'مراسلة المحل', onPressed: _openMessages, icon: const Icon(Icons.forum_rounded))]),
      body: Column(
        children: [
          OfflineNotice(visible: _offline),
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [CustomerColors.navy, CustomerColors.navyBright]),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [BoxShadow(color: CustomerColors.navy.withValues(alpha: .2), blurRadius: 20, offset: const Offset(0, 8))],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('الرصيد المتبقي', style: TextStyle(color: Color(0xFFBBD7FF), fontWeight: FontWeight.w600)),
              const SizedBox(height: 7),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 320),
                transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: ScaleTransition(scale: animation, child: child)),
                child: Text('${statement['balance']} ر.ي', key: ValueKey(statement['balance']), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 29)),
              ),
              const SizedBox(height: 8),
              const Row(children: [Icon(Icons.verified_rounded, color: CustomerColors.teal, size: 18), SizedBox(width: 6), Text('كشف حساب محدّث من المحل', style: TextStyle(color: Colors.white70, fontSize: 12))]),
            ]),
          ),
          const Padding(padding: EdgeInsets.fromLTRB(20, 8, 20, 6), child: Align(alignment: Alignment.centerRight, child: Text('سجل العمليات', style: TextStyle(fontWeight: FontWeight.w900, color: CustomerColors.navy, fontSize: 17)))),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              child: entries.isEmpty
                ? const Center(key: ValueKey('empty'), child: Text('لا توجد عمليات مسجلة حتى الآن'))
                : ListView.separated(
                    key: ValueKey('entries-${entries.length}-${entries.isEmpty ? '' : (entries.last as Map<String, dynamic>)['id'] ?? ''}'),
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: entries.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 9),
                    itemBuilder: (_, i) {
                      final entry = entries[i] as Map<String, dynamic>;
                      final effect = entry['effect']?.toString() ?? '';
                      final positive = effect.contains('payment') || effect.contains('credit');
                      return Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                          leading: Container(padding: const EdgeInsets.all(9), decoration: BoxDecoration(color: (positive ? CustomerColors.teal : CustomerColors.gold).withValues(alpha: .15), borderRadius: BorderRadius.circular(13)), child: Icon(positive ? Icons.south_west_rounded : Icons.receipt_long_rounded, color: positive ? CustomerColors.teal : const Color(0xFFB7791F))),
                          title: Text(entry['description']?.toString() ?? entry['type']?.toString() ?? 'عملية', style: const TextStyle(fontWeight: FontWeight.w800)),
                          subtitle: Text(entry['occurredAt']?.toString().split('T').first ?? ''),
                          trailing: Text(effect, style: TextStyle(fontWeight: FontWeight.w800, color: positive ? CustomerColors.teal : CustomerColors.navy)),
                        ),
                      );
                    },
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class CustomerMessagesScreen extends StatefulWidget {
  const CustomerMessagesScreen({super.key, required this.token, required this.shopId, required this.shopName});
  final String token; final String shopId; final String shopName;
  @override
  State<CustomerMessagesScreen> createState() => _CustomerMessagesScreenState();
}

class _CustomerMessagesScreenState extends State<CustomerMessagesScreen>
    with WidgetsBindingObserver {
  final _message = TextEditingController();
  final _scroll = ScrollController();
  List<Map<String, dynamic>> _messages = const [];
  Timer? _poller;
  bool _offline = false;
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restoreCache();
    _load();
    _poller = Timer.periodic(const Duration(seconds: 7), (_) => _load());
  }
  @override
  void dispose() { WidgetsBinding.instance.removeObserver(this); _poller?.cancel(); _message.dispose(); _scroll.dispose(); super.dispose(); }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _restoreCache() async {
    final cached = await _readListCache(_messagesCacheKey(widget.shopId));
    if (mounted && cached != null) setState(() { _messages = cached.cast<Map<String, dynamic>>(); _loading = false; });
  }

  Future<void> _load() async {
    try {
      final response = await http.get(Uri.parse('$_apiBase/api/v1/shops/${widget.shopId}/my-messages'), headers: {'authorization': 'Bearer ${widget.token}'}).timeout(const Duration(seconds: 12));
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200) throw const FormatException();
      final items = (payload['data'] as Map<String, dynamic>)['items'] as List<dynamic>? ?? const [];
      await _saveCache(_messagesCacheKey(widget.shopId), items);
      if (!mounted) return;
      final hadNewMessages = items.length > _messages.length;
      setState(() { _messages = items.cast<Map<String, dynamic>>(); _offline = false; _loading = false; });
      if (hadNewMessages) _scrollToLatest();
    } catch (_) {
      if (mounted) setState(() { _offline = true; _loading = false; });
    }
  }

  Future<void> _send() async {
    final body = _message.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final response = await http.post(Uri.parse('$_apiBase/api/v1/shops/${widget.shopId}/my-messages'), headers: {'authorization': 'Bearer ${widget.token}', 'content-type': 'application/json'}, body: jsonEncode({'body': body})).timeout(const Duration(seconds: 12));
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode < 200 || response.statusCode >= 300) throw const FormatException();
      if (!mounted) return;
      _message.clear();
      final messages = [..._messages, (payload['data'] as Map<String, dynamic>)];
      await _saveCache(_messagesCacheKey(widget.shopId), messages);
      setState(() { _messages = messages; _sending = false; _offline = false; });
      _scrollToLatest();
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر إرسال الرسالة. حاول مجددًا.')));
    }
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
    });
  }

  String _time(Object? iso) {
    final value = iso?.toString() ?? '';
    return value.length >= 16 ? value.substring(11, 16) : '';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Column(mainAxisSize: MainAxisSize.min, children: [const Text('مراسلة المحل'), Text(widget.shopName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400))])),
    body: Column(children: [
      OfflineNotice(visible: _offline),
      Expanded(child: _content()),
      SafeArea(top: false, child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Color(0xFFE5E7EB)))),
        child: Row(children: [
          Expanded(child: TextField(controller: _message, minLines: 1, maxLines: 4, maxLength: 2000, decoration: const InputDecoration(hintText: 'اكتب رسالة للمحل…', counterText: '', border: OutlineInputBorder()))),
          const SizedBox(width: 8),
          IconButton.filled(onPressed: _sending ? null : _send, tooltip: 'إرسال', icon: _sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send_rounded)),
        ]),
      )),
    ]),
  );

  Widget _content() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_messages.isEmpty) {
      return _offline
          ? OfflineEmptyPanel(onRetry: _load)
          : const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.forum_outlined, size: 48, color: CustomerColors.navy), SizedBox(height: 10), Text('ابدأ محادثتك مع المحل برسالة واضحة.')]));
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      itemCount: _messages.length,
      itemBuilder: (_, i) {
        final item = _messages[i];
        final mine = item['senderType'] == 'customer';
        return TweenAnimationBuilder<double>(
          key: ValueKey(item['id']),
          duration: const Duration(milliseconds: 280),
          tween: Tween(begin: 0, end: 1),
          builder: (_, value, child) => Opacity(opacity: value, child: Transform.translate(offset: Offset(0, 14 * (1 - value)), child: child)),
          child: Align(alignment: mine ? Alignment.centerRight : Alignment.centerLeft, child: Container(
          constraints: const BoxConstraints(maxWidth: 310),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 7),
          decoration: BoxDecoration(color: mine ? CustomerColors.navy : Colors.white, borderRadius: BorderRadius.circular(16), border: mine ? null : Border.all(color: const Color(0xFFE5E7EB))),
          child: Column(crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
            Text(item['body']?.toString() ?? '', style: TextStyle(color: mine ? Colors.white : const Color(0xFF1F2933))),
            const SizedBox(height: 4),
            Text(_time(item['createdAt']), style: TextStyle(fontSize: 10, color: mine ? Colors.white70 : const Color(0xFF6B7280))),
          ]),
        )),
        );
      },
    );
  }
}

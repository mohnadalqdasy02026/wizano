import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../features/auth/auth_controller.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/splash_screen.dart';
import '../features/customers/customer_controller.dart';
import '../features/finance/finance_controller.dart';
import '../features/home/home_shell.dart';
import '../features/payments/payment_controller.dart';
import '../features/purchases/purchase_controller.dart';
import '../features/shop/shop_controller.dart';
import '../features/shop/shop_setup_screen.dart';
import '../features/sync/sync_controller.dart';

/// الجذر: يوجّه تلقائيًا حسب حالة الجلسة والمحل.
///
/// - جلسة غير معروفة → S01 Splash.
/// - غير مُصادَق → S02 تسجيل الدخول.
/// - مُصادَق بلا محل → S04 إعداد المحل.
/// - مُصادَق مع محل → S07 الشل/لوحة التحكم.
class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> with WidgetsBindingObserver {
  bool _shopsLoaded = false;
  String? _customerShopId;
  String? _purchaseShopId;
  String? _paymentShopId;
  String? _financeShopId;
  String? _syncShopId;
  Timer? _backgroundSync;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // مزامنة صامتة متكررة: لا يحتاج صاحب المحل لسحب الشاشة أو فتح صفحة
    // المزامنة كي تصل عملياته المحفوظة محليًا إلى الخادم أو تظهر التحديثات.
    _backgroundSync = Timer.periodic(
      const Duration(seconds: 8),
      (_) => _refreshSilently(),
    );
  }

  @override
  void dispose() {
    _backgroundSync?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _refreshSilently() async {
    if (!mounted || _refreshing) return;
    final sync = context.read<SyncController>();
    if (sync.shopId == null) return;
    _refreshing = true;
    try {
      await sync.syncNow();
      if (!mounted) return;
      await Future.wait([
        context.read<CustomerController>().load(),
        context.read<PurchaseController>().load(),
        context.read<PaymentController>().load(),
      ]);
    } finally {
      _refreshing = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // العودة إلى التطبيق: فرصة ذهبية لفراغ الطابور إن كان الاتصال قد عاد.
    // لا نعتمد على عدّاد قديم في الذاكرة: الاستعلام من قاعدة البيانات أرخص
    // من خطأ تفويت المزامنة.
    if (state != AppLifecycleState.resumed) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _refreshSilently();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final shops = context.watch<ShopController>();
    final customers = context.watch<CustomerController>();
    final purchases = context.watch<PurchaseController>();
    final payments = context.watch<PaymentController>();
    final finance = context.watch<FinanceController>();
    final sync = context.watch<SyncController>();

    if (auth.isAuthenticated && !_shopsLoaded) {
      _shopsLoaded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await shops.load();
        if (mounted && shops.active != null) {
          await auth.setActiveShopId(shops.active!.id);
        }
      });
    }
    if (!auth.isAuthenticated) {
      _shopsLoaded = false;
      _customerShopId = null;
      _purchaseShopId = null;
      _paymentShopId = null;
      _financeShopId = null;
      _syncShopId = null;
    }

    // مزامنة المحل النشط مع قسم العملاء وتحميلهم عند تغيّره.
    final activeShopId = shops.active?.id;
    if (activeShopId != null && activeShopId != _customerShopId) {
      _customerShopId = activeShopId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        customers.setShop(activeShopId);
        customers.load();
      });
    }

    // مزامنة المحل النشط مع قسم المشتريات وتحميلها عند تغيّره.
    if (activeShopId != null && activeShopId != _purchaseShopId) {
      _purchaseShopId = activeShopId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        purchases.setShop(activeShopId);
        purchases.load();
      });
    }

    // مزامنة المحل النشط مع قسم المدفوعات وتحميلها عند تغيّره.
    if (activeShopId != null && activeShopId != _paymentShopId) {
      _paymentShopId = activeShopId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        payments.setShop(activeShopId);
        payments.load();
      });
    }

    // مزامنة المحل النشط مع قسم المالية (المرتجعات/التصحيحات/الإلغاءات) عند تغيّره.
    if (activeShopId != null && activeShopId != _financeShopId) {
      _financeShopId = activeShopId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        finance.setShop(activeShopId);
      });
    }

    // التعافي عند الإقلاع: فحص طابور المزامنة والحالات العالقة (docs/04 §7).
    if (activeShopId != null && activeShopId != _syncShopId) {
      _syncShopId = activeShopId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        sync.setShop(activeShopId);
        sync.load();
      });
    }

    switch (auth.status) {
      case AuthStatus.unknown:
        return const SplashScreen();
      case AuthStatus.unauthenticated:
        return const LoginScreen();
      case AuthStatus.authenticated:
        if (shops.loading && shops.shops.isEmpty) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return shops.hasShop ? const HomeShell() : const ShopSetupScreen();
    }
  }
}

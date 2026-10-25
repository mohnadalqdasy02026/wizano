import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'app/app_root.dart';
import 'app/theme.dart';
import 'core/connectivity.dart';
import 'core/secure_token_store.dart';
import 'core/token_store.dart';
import 'data/local/local_database.dart';
import 'data/local/sqlite_local_store.dart';
import 'data/repositories/offline_first_repository.dart';
import 'data/remote/api_client.dart';
import 'data/repositories/auth_repository.dart';
import 'features/auth/auth_controller.dart';
import 'features/customers/customer_controller.dart';
import 'features/finance/finance_controller.dart';
import 'features/payments/payment_controller.dart';
import 'features/purchases/purchase_controller.dart';
import 'features/shop/shop_controller.dart';
import 'features/speech/speech_controller.dart';
import 'features/statements/statement_controller.dart';
import 'features/sync/sync_controller.dart';
import 'services/speech/model_manager.dart';
import 'services/speech/speech_service.dart';

void main() {
  runApp(const WizanoShopApp());
}

class WizanoShopApp extends StatelessWidget {
  const WizanoShopApp({super.key, ApiClient? apiClient, TokenStore? tokenStore})
      : _apiClientOverride = apiClient,
        _tokenStoreOverride = tokenStore;

  final ApiClient? _apiClientOverride;
  final TokenStore? _tokenStoreOverride;

  @override
  Widget build(BuildContext context) {
    final tokenStore = _tokenStoreOverride ?? SecureTokenStore();
    final apiClient =
        _apiClientOverride ?? ApiClient(tokenStore: tokenStore);

    return MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: apiClient),
        Provider<AuthRepository>(
          create: (_) =>
              ApiAuthRepository(api: apiClient, tokenStore: tokenStore),
        ),
        Provider<LocalDatabase>(
          create: (_) => LocalDatabase(),
        ),
        Provider<SqliteLocalStore>(
          create: (ctx) => SqliteLocalStore(ctx.read<LocalDatabase>()),
        ),
        ChangeNotifierProvider<ConnectivityMonitor>(
          create: (_) => ConnectivityMonitor(),
        ),
        Provider<OfflineFirstRepository>(
          create: (ctx) => OfflineFirstRepository(
            api: apiClient,
            queue: ctx.read<SqliteLocalStore>(),
            monitor: ctx.read<ConnectivityMonitor>(),
          ),
        ),
        ChangeNotifierProvider<AuthController>(
          create: (ctx) {
            // نلتقط نسخة قاعدة البيانات الآن: مسحها عند الخروج يمنع
            // انتقال عمليات معلّقة إلى حساب آخر.
            final database = ctx.read<LocalDatabase>();
            return AuthController(
              repository: ctx.read<AuthRepository>(),
              onLogout: database.clearAll,
            );
          },
        ),
        ChangeNotifierProvider<ShopController>(
          create: (ctx) => ShopController(
            api: apiClient,
            repository: ctx.read<OfflineFirstRepository>(),
          ),
        ),
        ChangeNotifierProvider<CustomerController>(
          create: (ctx) => CustomerController(
            api: apiClient,
            repository: ctx.read<OfflineFirstRepository>(),
          ),
        ),
        ChangeNotifierProvider<PurchaseController>(
          create: (ctx) => PurchaseController(
            repository: ctx.read<OfflineFirstRepository>(),
          ),
        ),
        ChangeNotifierProvider<PaymentController>(
          create: (ctx) => PaymentController(
            repository: ctx.read<OfflineFirstRepository>(),
          ),
        ),
        ChangeNotifierProvider<SyncController>(
          create: (ctx) => SyncController(
            repository: ctx.read<OfflineFirstRepository>(),
          ),
        ),
        ChangeNotifierProvider<FinanceController>(
          create: (_) => FinanceController(api: apiClient),
        ),
        ChangeNotifierProvider<StatementController>(
          create: (ctx) => StatementController(api: apiClient),
        ),
        ChangeNotifierProvider<SpeechController>(
          // غير كسول: يُفحص النموذج على القرص عند إقلاع التطبيق لا عند أول
          // استخدام للوحة، وإلا ظنّ التطبيق أن النموذج غير محمّل.
          lazy: false,
          create: (_) => SpeechController(
            modelManager: ModelManager(),
            speechService: SpeechService(),
          ),
        ),
      ],
      child: MaterialApp(
        title: 'WIZANO',
        debugShowCheckedModeBanner: false,
        theme: WizanoTheme.light,
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        ),
        home: const AppRoot(),
      ),
    );
  }
}



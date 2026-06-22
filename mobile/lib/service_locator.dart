/// Service Locator — Injeção de dependência via GetIt.
///
/// Registra e configura todas as dependências da aplicação.
/// Chamado uma única vez em main.dart antes de runApp.
library;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'core/cart/cart_notifier.dart';
import 'core/config/app_config_service.dart';
import 'core/database/database_helper.dart';
import 'core/network/auto_sync_service.dart';
import 'core/network/jwt_interceptor.dart';
import 'core/network/connectivity_service.dart';
import 'core/repositories/customer_repository.dart';
import 'core/repositories/financial_repository.dart';
import 'core/repositories/natureza_operacao_repository.dart';
import 'core/repositories/order_repository.dart';
import 'core/repositories/payment_species_repository.dart';
import 'core/repositories/payment_condition_repository.dart';
import 'core/repositories/performance_repository.dart';
import 'core/repositories/product_repository.dart';
import 'core/session/session_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/order_notification_service.dart';
import 'core/services/dashboard_service.dart';
import 'core/services/customer_service.dart';
import 'core/services/favorite_service.dart';
import 'core/services/order_service.dart';
import 'core/services/order_pdf_service.dart';
import 'core/sync/cache_warm_service.dart';
import 'core/sync/sync_service.dart';
import 'core/services/company_settings_service.dart';

final GetIt locator = GetIt.instance;

/// Configura todas as dependências da aplicação.
/// Chamar ANTES de [runApp].
Future<void> setupLocator() async {
  debugPrint('[DI] Starting setupLocator');
  
  // ── Config — URL e API Key persistidas (#9) ──────────────────────────────
  debugPrint('[DI] Loading AppConfigService');
  final config = AppConfigService();
  await config.initializeDefaults(); // Preenche defaults apenas se não configurado
  locator.registerSingleton<AppConfigService>(config);

  final serverUrl = await config.getServerUrl();
  final accessToken = await config.getAccessToken();
  debugPrint('[DI] Server URL: $serverUrl');

  // ── Infrastructure ──────────────────────────────────────────────────────
  debugPrint('[DI] Registering DatabaseHelper');
  locator.registerSingleton<DatabaseHelper>(DatabaseHelper());

  // HTTP Client com URL base carregada do AppConfigService
  debugPrint('[DI] Creating Dio instance');
  final dio = Dio(
    BaseOptions(
      baseUrl:        serverUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Content-Type': 'application/json',
        if (accessToken != null && accessToken.isNotEmpty)
          'Authorization': 'Bearer $accessToken',
      },
    ),
  );

  // ── Session (Fase 3) ──────────────────────────────────────────────────────
  // Necessário instanciar antes para injetar no JwtInterceptor
  debugPrint('[DI] Initializing SessionService');
  final sessionService = SessionService(db: locator<DatabaseHelper>());
  try {
    await sessionService.initialize();
  } catch (e) {
    debugPrint('[DI] WARNING: SessionService failed to initialize: $e');
  }
  locator.registerSingleton<SessionService>(sessionService);

  // Interceptador de JWT
  dio.interceptors.add(JwtInterceptor(sessionService));

  // Interceptor de logging
  dio.interceptors.add(LogInterceptor(
    requestBody:  false,
    responseBody: false,
    logPrint: (log) => debugLog(log.toString()),
  ));
  locator.registerSingleton<Dio>(dio);

  // ── Services ─────────────────────────────────────────────────────────────
  debugPrint('[DI] Initializing ConnectivityService');
  final connectivity = ConnectivityService();
  connectivity.initialize().catchError((e) {
    debugPrint('[DI] WARNING: ConnectivityService failed to initialize: $e');
  });
  locator.registerSingleton<ConnectivityService>(connectivity);

  // Serviço de notificações locais (Feature D)
  debugPrint('[DI] Initializing NotificationService');
  final notifications = NotificationService();
  notifications.initialize().catchError((e) {
    debugPrint('[DI] WARNING: NotificationService failed to initialize: $e');
  });
  locator.registerSingleton<NotificationService>(notifications);

  // Motor de sincronização offline-first
  debugPrint('[DI] Registering SyncService');
  final syncService = SyncService(
    db:            locator<DatabaseHelper>(),
    connectivity:  locator<ConnectivityService>(),
    dio:           locator<Dio>(),
    notifications: notifications,
  );
  locator.registerSingleton<SyncService>(syncService);

  // Configurações comportamentais da empresa (priceTableMode)
  debugPrint('[DI] Loading CompanySettingsService');
  final companySettings = CompanySettingsService();
  await companySettings.load();
  locator.registerSingleton<CompanySettingsService>(companySettings);

  // Serviço de notificação de pedidos confirmados (M3)
  debugPrint('[DI] Registering OrderNotificationService');
  locator.registerLazySingleton<OrderNotificationService>(
    () => OrderNotificationService(dio: locator<Dio>()),
  );

  // Serviço de re-aquecimento de cache Redis (M2)
  debugPrint('[DI] Registering CacheWarmService');
  locator.registerLazySingleton<CacheWarmService>(
    () => CacheWarmService(db: locator<DatabaseHelper>(), dio: locator<Dio>()),
  );

  // ── Repositories (Fase 2) ────────────────────────────────────────────────
  debugPrint('[DI] Registering Repositories');
  locator.registerSingleton<ProductRepository>(
    ProductRepository(db: locator<DatabaseHelper>()),
  );

  locator.registerSingleton<OrderRepository>(
    OrderRepository(
      db:   locator<DatabaseHelper>(),
      sync: locator<SyncService>(),
    ),
  );

  // ── State Management (Fase 2) ────────────────────────────────────────────
  debugPrint('[DI] Registering CartNotifier');
  locator.registerSingleton<CartNotifier>(
    CartNotifier(repo: locator<OrderRepository>()),
  );

  // ── SessionService transferido para cima devido ao JwtInterceptor ──

  // ── Customer (Fase 3) ─────────────────────────────────────────────────────
  debugPrint('[DI] Registering Customer/Payment/Financial Repositories');
  locator.registerSingleton<CustomerRepository>(
    CustomerRepository(db: locator<DatabaseHelper>()),
  );

  locator.registerSingleton<PaymentSpeciesRepository>(
    PaymentSpeciesRepository(db: locator<DatabaseHelper>()),
  );

  locator.registerSingleton<PaymentConditionRepository>(
    PaymentConditionRepository(locator<DatabaseHelper>()),
  );

  locator.registerSingleton<NaturezaOperacaoRepository>(
    NaturezaOperacaoRepository(db: locator<DatabaseHelper>()),
  );

  locator.registerSingleton<FinancialRepository>(
    FinancialRepository(db: locator<DatabaseHelper>()),
  );

  locator.registerSingleton<PerformanceRepository>(
    PerformanceRepository(locator<DatabaseHelper>()),
  );

  // ── Application Services (Phase 2 Evolution) ────────────────────────────
  debugPrint('[DI] Registering Application Services');
  locator.registerLazySingleton<DashboardService>(
    () => DashboardService(locator<DatabaseHelper>()),
  );
  locator.registerLazySingleton<CustomerService>(
    () => CustomerService(locator<DatabaseHelper>()),
  );
  locator.registerLazySingleton<OrderService>(
    () => OrderService(locator<DatabaseHelper>()),
  );
  locator.registerLazySingleton<FavoriteService>(
    () => FavoriteService(locator<DatabaseHelper>()),
  );
  locator.registerLazySingleton<OrderPdfService>(
    () => OrderPdfService(locator<DatabaseHelper>()),
  );

  // ── Auto Sync (Fase 3) ────────────────────────────────────────────────────
  debugPrint('[DI] Registering AutoSyncService');
  final autoSync = AutoSyncService(
    sync:         locator<SyncService>(),
    connectivity: locator<ConnectivityService>(),
    session:      locator<SessionService>(),
  );
  locator.registerSingleton<AutoSyncService>(autoSync);
  
  if (!kIsWeb) {
    debugPrint('[DI] Starting AutoSyncService');
    autoSync.start();

    // Cache Warm — re-popula Redis ao iniciar se houver dados locais
    if (locator<ConnectivityService>().currentStatus == ConnectivityStatus.online) {
      debugPrint('[DI] Online at startup — triggering cache warm');
      locator<CacheWarmService>().warmAll().catchError(
        (e) => debugPrint('[DI] CacheWarm startup warning: $e'),
      );
    }
  } else {
    debugPrint('[DI] AutoSyncService/CacheWarm disabled for web simulation');
  }
  
  debugPrint('[DI] setupLocator COMPLETED');
}

/// Log de debug — desligado em produção automaticamente pelo compilador.
void debugLog(String message) {
  // ignore: avoid_print
  assert(() { if (kDebugMode) debugPrint('[DI] $message'); return true; }());
}

import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite/sqflite.dart';
import 'core/database/sqlite_ffi.dart';
import 'core/config/app_config_service.dart';
import 'core/config/app_version.dart';
import 'core/device/device_id_service.dart';
import 'service_locator.dart';
import 'core/design/app_theme.dart';
import 'core/session/session_service.dart';
import 'features/activation/device_blocked_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/activation/activation_screen.dart';
import 'features/auth/branch_selection_screen.dart';
import 'features/home/main_navigation_scaffold.dart';
import 'features/splash/splash_screen.dart';

Future<void> main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    debugPrint('[MAIN] Starting application...');

    // Inicializa SQLite FFI para Windows/Linux desktop (via conditional import)
    if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.windows || defaultTargetPlatform == TargetPlatform.linux)) {
      debugPrint('[MAIN] Initializing SQLite FFI');
      initSqliteFfi();
      databaseFactory = ffiDatabaseFactory;
    }

    debugPrint('[MAIN] Setting up locale and orientation');
    await initializeDateFormatting('pt_BR', null);

    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor:                Colors.transparent,
      statusBarIconBrightness:       Brightness.light,
      systemNavigationBarColor:      Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
    ));

    // edgeToEdge: app desenha atrÃ¡s da status bar e navigation bar.
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    debugPrint('[MAIN] Setting up locator...');
    try {
      await setupLocator();
      debugPrint('[MAIN] Locator setup complete');
    } catch (e, stack) {
      debugPrint('[MAIN] FATAL ERROR in setupLocator: $e');
      debugPrint(stack.toString());
    }

    debugPrint('[MAIN] App initialization finished, running App');
    runApp(const ColiseuSalesApp());
  }, (error, stack) {
    debugPrint('[MAIN] UNHANDLED ERROR: $error');
    debugPrint(stack.toString());
  });
}

class ColiseuSalesApp extends StatelessWidget {
  const ColiseuSalesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Coliseu App',
      debugShowCheckedModeBanner: false,
      theme:     AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.light,
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [
        Locale('pt', 'BR'),
        Locale('en', 'US'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routes: {
        '/home': (context) => const MainNavigationScaffold(),
        '/auth-gate': (context) => const AuthGate(),
        '/branch-selection': (context) => const BranchSelectionScreen(),
      },
      home: SplashScreen(nextScreen: const AuthGate()),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AuthGate — Verifica ativação + status do dispositivo + sessão
// ─────────────────────────────────────────────────────────────────────────────

/// Estados do fluxo de verificação do dispositivo.
enum _DeviceState {
  checking,     // verificando com the Identity Server (estado inicial)
  notActivated, // sem chave de ativação salva → ActivationScreen
  blocked,      // Identity Server retornou 403 (revogado ou inativo)
  active,       // dispositivo autorizado → LoginScreen / MainNav
}

/// Guard reativo:
/// 1. Sem chave de ativação salva      → ActivationScreen
/// 2. Online + Identity retorna 403    → DeviceBlockedScreen (licença revogada)
/// 3. Online + Identity retorna 200    → renova tokens → SessionGate normal
/// 4. Offline / erro de rede           → continua com tokens locais (offline-first)
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _config      = AppConfigService();
  final _deviceIdSvc = DeviceIdService();

  _DeviceState _state         = _DeviceState.checking;
  String?      _blockedReason;
  bool         _hasBranchSelected = false;

  @override
  void initState() {
    super.initState();
    _checkDevice();
  }

  Future<void> _setDeviceActive() async {
    final hasBranch = await _config.hasBranchSelected();
    if (mounted) {
      setState(() {
        _hasBranchSelected = hasBranch;
        _state = _DeviceState.active;
      });
    }
  }

  /// Verifica ativação local E status online do dispositivo.
  ///
  /// Se não houver conexão com o Identity Server, permite o uso offline
  /// com os tokens armazenados localmente (comportamento offline-first).
  Future<void> _checkDevice() async {
    // ── 1. Verifica chave de ativação local ────────────────────────
    final activationKey = await _config.getActivationKey();
    if (activationKey == null || activationKey.isEmpty) {
      if (mounted) setState(() => _state = _DeviceState.notActivated);
      return;
    }

    // ── 2. Verifica status no Identity Server ──────────────────────
    try {
      final identityUrl = await _config.getIdentityUrl();
      if (identityUrl == null || identityUrl.isEmpty) {
        debugPrint('[AuthGate] identityUrl não configurada — modo offline permitido');
        await _setDeviceActive();
        return;
      }
      final deviceId    = await _deviceIdSvc.getDeviceId();
      final info        = await _deviceIdSvc.getDeviceInfo();

      final dio = Dio(BaseOptions(
        baseUrl:        identityUrl,
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ));

      final resp = await dio.post('/auth/device-login', data: {
        'activationKey': activationKey,
        'deviceUuid':    deviceId,
        'model':         info.model,
        'os':            info.os,
        'appVersion':    kAppVersion,
      });

      if (resp.statusCode == 200 || resp.statusCode == 201) {
        // Renova tokens automaticamente na abertura do app
        final data = resp.data as Map<String, dynamic>;
        if (data['accessToken']  != null) await _config.setAccessToken(data['accessToken']);
        if (data['refreshToken'] != null) await _config.setRefreshToken(data['refreshToken']);
        debugPrint('[AuthGate] Dispositivo verificado ✔ tokens renovados');
        await _setDeviceActive();
      }
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;

      if (statusCode == 403 || statusCode == 401) {
        // ── Dispositivo revogado — bloqueia imediatamente ────────────
        final errorMsg = e.response?.data?['error']
            ?? e.response?.data?['message']
            ?? 'Dispositivo não autorizado (código $statusCode)';

        debugPrint('[AuthGate] Dispositivo revogado: $errorMsg');

        // Limpa tokens mas preserva chave (para exibir a tela de bloqueio)
        await _config.setAccessToken('');
        await _config.setRefreshToken('');

        if (mounted) {
          setState(() {
            _state         = _DeviceState.blocked;
            _blockedReason = errorMsg;
          });
        }
        return;
      }

      // Erro de rede (timeout, sem internet) — modo offline permitido
      debugPrint('[AuthGate] Identity offline — modo offline: ${e.message}');
      await _setDeviceActive();

    } catch (e) {
      // Erro inesperado — permite uso offline por segurança
      debugPrint('[AuthGate] Erro inesperado (offline permitido): $e');
      await _setDeviceActive();
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_state) {
      case _DeviceState.checking:
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );

      case _DeviceState.notActivated:
        return ActivationScreen(
          key: const ValueKey('activation'),
          onActivated: () {
            setState(() => _state = _DeviceState.checking);
            _checkDevice();
          },
        );

      case _DeviceState.blocked:
        return DeviceBlockedScreen(
          reason: _blockedReason,
          onReactivate: () {
            setState(() => _state = _DeviceState.notActivated);
          },
        );

      case _DeviceState.active:
        if (!_hasBranchSelected) {
          return const BranchSelectionScreen(key: ValueKey('branchSelector'));
        }
        final session = GetIt.I<SessionService>();
        return ValueListenableBuilder<SessionState>(
          valueListenable: session.stateNotifier,
          builder: (_, state, __) => AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: state == SessionState.authenticated
                ? const MainNavigationScaffold(key: ValueKey('home'))
                : const LoginScreen(key: ValueKey('login')),
          ),
        );
    }
  }
}


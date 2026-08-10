import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/design/app_theme.dart';
import 'features/camera/presentation/providers/camera_session_provider.dart';
import 'features/splash/presentation/pages/splash_page.dart';
import 'core/network/sync_service.dart';
import 'core/network/auto_sync_service.dart';
import 'features/vehicle/presentation/providers/vehicle_search_provider.dart';
import 'features/vehicle/domain/repositories/vehicle_repository.dart';
import 'features/auth/presentation/providers/auth_provider.dart';
import 'features/auth/domain/repositories/sellers_repository.dart';
import 'core/network/auth/auth_token_manager.dart';

import 'core/di/injection.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Configura ErrorWidget.builder o mais cedo possível para capturar erros de UI de forma segura
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Material(
      color: Colors.white,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.bug_report, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              const Text(
                'Erro de Renderização (UI)',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
              const SizedBox(height: 16),
              SelectableText(
                details.exception.toString(),
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
              ),
              const SizedBox(height: 16),
              const Divider(),
              SelectableText(
                details.stack.toString(),
                style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: Colors.black54),
              ),
            ],
          ),
        ),
      ),
    );
  };

  // Garante inicialização e log do app antes do runApp
  String? initError;
  String? initStackTrace;
  try {
    setupDependencies();
    
    // Inicializando a Fila de Background
    await SyncService.initialize();

    // Inicializando o Monitoramento e Fila de Sincronia
    AutoSyncService.instance.initialize();
  } catch (e, stack) {
    initError = e.toString();
    initStackTrace = stack.toString();
  }

  if (initError != null) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error, color: Colors.red, size: 48),
                  const SizedBox(height: 16),
                  const Text(
                    'Erro Crítico na Inicialização',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.red),
                  ),
                  const SizedBox(height: 16),
                  SelectableText(
                    initError,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  const Text('Rastreamento de Pilha:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  SelectableText(
                    initStackTrace ?? '',
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return;
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CameraSessionProvider()),
        ChangeNotifierProvider(
          create: (_) => VehicleSearchProvider(
            repository: getIt<VehicleRepository>(),
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => AuthProvider(
            sellersRepository: getIt<SellersRepository>(),
            tokenManager: getIt<AuthTokenManager>(),
          ),
        ),
      ],
      child: const AutoCenterApp(),
    ),
  );
}

class AutoCenterApp extends StatelessWidget {
  const AutoCenterApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Coliseu AutoCenter',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.lightTheme, // Force light para manter o branding em SO escuro
      themeMode: ThemeMode.light,
      debugShowCheckedModeBanner: false,
      home: const SplashPage(),
    );
  }
}

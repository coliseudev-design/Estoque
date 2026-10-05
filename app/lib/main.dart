import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app/services.dart';
import 'app/theme.dart';
import 'features/activation/activation_screen.dart';
import 'features/documents/documents_screen.dart';
import 'features/login/login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  final services = await AppServices.create();
  runApp(Services(services: services, child: const ColiseuEstoqueApp()));
}

class ColiseuEstoqueApp extends StatelessWidget {
  const ColiseuEstoqueApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Coliseu Estoque',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const _Gate(),
    );
  }
}

/// Decide a tela inicial: ativação do aparelho → login do operador → fila de documentos.
class _Gate extends StatelessWidget {
  const _Gate();

  @override
  Widget build(BuildContext context) {
    final session = Services.of(context).session;
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        if (!session.isActivated) return const ActivationScreen();
        if (!session.isLoggedIn) return const LoginScreen();
        return const DocumentsScreen();
      },
    );
  }
}

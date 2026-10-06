import 'package:flutter/material.dart';

/// Mesmas cores do painel web: azul da marca, ciano = entrada, violeta = saída.
class AppColors {
  static const brand = Color(0xFF1E74C4);
  static const brand2 = Color(0xFF2B9BE0);
  static const ok = Color(0xFF059669);
  static const warn = Color(0xFFD97706);
  static const danger = Color(0xFFDC2626);
  static const entrada = Color(0xFF0891B2);
  static const saida = Color(0xFF7C3AED);
  static const wait = Color(0xFF6366F1);
  static const sep = Color(0xFF2563EB);
}

Color flowColor(String flow) => flow == 'entrada' ? AppColors.entrada : AppColors.saida;

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: AppColors.brand, brightness: brightness);
  final dark = brightness == Brightness.dark;
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    visualDensity: VisualDensity.standard,
    scaffoldBackgroundColor: dark ? const Color(0xFF0B1017) : const Color(0xFFF4F6FB),
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? const Color(0xFF131A24) : Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 1,
      titleTextStyle: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: scheme.onSurface),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      filled: true,
      fillColor: dark ? const Color(0xFF18212D) : Colors.white,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        backgroundColor: AppColors.brand,
        foregroundColor: Colors.white,
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(50),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: dark ? const Color(0xFF131A24) : Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: dark ? const Color(0xFF243142) : const Color(0xFFE3E8EF)),
      ),
    ),
  );
}

Color statusColor(String status) => switch (status) {
      'AGUARDANDO' => AppColors.wait,
      'EM_CONFERENCIA' => AppColors.sep,
      'DIVERGENTE' => AppColors.warn,
      'AGUARDANDO_APROVACAO' => AppColors.danger,
      'CONCLUIDO' => AppColors.ok,
      _ => Colors.grey,
    };

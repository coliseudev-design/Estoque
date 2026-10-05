import 'package:flutter/material.dart';

class AppColors {
  static const brand = Color(0xFF1F8FE0);
  static const ok = Color(0xFF16A34A);
  static const warn = Color(0xFFD97706);
  static const danger = Color(0xFFDC2626);
}

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: AppColors.brand, brightness: brightness);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    visualDensity: VisualDensity.standard,
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      filled: true,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
  );
}

Color statusColor(String status) => switch (status) {
      'EM_CONFERENCIA' => AppColors.brand,
      'DIVERGENTE' => AppColors.warn,
      'AGUARDANDO_APROVACAO' => AppColors.danger,
      'CONCLUIDO' => AppColors.ok,
      _ => Colors.grey,
    };

library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

abstract final class AppTheme {
  /// O AutoCenter App adota o Light Mode com branding Coliseu,
  /// mantendo consistência com o restante do ecossistema (Cloud e Vendas).
  static ThemeData get lightTheme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorSchemeSeed: AppColors.primary,
    scaffoldBackgroundColor: AppColors.surface,

    // ── Typography ────────────────────────────────────────────────────
    textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme).copyWith(
      headlineLarge: AppTypography.headingLarge.copyWith(color: AppColors.textPrimary),
      headlineMedium: AppTypography.headingMedium.copyWith(color: AppColors.textPrimary),
      titleLarge:    AppTypography.headingLarge.copyWith(color: AppColors.textPrimary),
      titleMedium:   AppTypography.label.copyWith(color: AppColors.textPrimary),
      bodyLarge:     AppTypography.body.copyWith(color: AppColors.textPrimary),
      bodyMedium:    AppTypography.body.copyWith(color: AppColors.textPrimary),
      bodySmall:     AppTypography.caption.copyWith(color: AppColors.textSecondary),
      labelLarge:    AppTypography.button.copyWith(color: AppColors.textPrimary),
    ),

    // ── AppBar ────────────────────────────────────────────────────────
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 1,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: AppTypography.headingLarge.copyWith(color: AppColors.textPrimary),
      iconTheme: const IconThemeData(color: AppColors.textSecondary, size: 24),
    ),

    // ── NavigationBar (BottomTabs) ────────────────────────────────────
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surfaceElevated,
      elevation: 0,
      height: 72,
      indicatorColor: AppColors.accent.withValues(alpha: 0.15),
      surfaceTintColor: Colors.transparent,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppTypography.caption.copyWith(color: AppColors.accent, fontWeight: FontWeight.w700);
        }
        return AppTypography.caption.copyWith(color: AppColors.textSecondary);
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: AppColors.accent, size: 24);
        }
        return const IconThemeData(color: AppColors.textSecondary, size: 24);
      }),
    ),

    // ── Cards (Módulo Glass) ──────────────────────────────────────────
    cardTheme: CardThemeData(
      color: AppColors.surfaceElevated,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.cardRadius,
        side: const BorderSide(color: AppColors.border, width: 1),
      ),
      margin: EdgeInsets.zero,
    ),

    // ── Botoões Principais ────────────────────────────────────────────
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        elevation: 0,
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.buttonRadius),
        textStyle: AppTypography.button,
      ),
    ),

    // ── Inputs ────────────────────────────────────────────────────────
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceMuted,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: AppRadius.inputRadius,
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: AppRadius.inputRadius,
        borderSide: const BorderSide(color: AppColors.border, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: AppRadius.inputRadius,
        borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
      ),
      hintStyle: AppTypography.body.copyWith(color: AppColors.textTertiary),
      labelStyle: AppTypography.label.copyWith(color: AppColors.textSecondary),
      floatingLabelStyle: AppTypography.label.copyWith(color: AppColors.accent),
    ),
    
    // Bottom Sheet
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: AppColors.surfaceElevated,
      modalBackgroundColor: AppColors.surfaceElevated,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.sheetRadius),
      showDragHandle: true,
      dragHandleColor: AppColors.textTertiary,
    ),
    
    // SnackBar
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.surfaceElevated,
      contentTextStyle: AppTypography.body.copyWith(color: AppColors.textPrimary),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.cardRadius),
    ),
  );
}

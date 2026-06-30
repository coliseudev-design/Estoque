/// MaterialTheme — Design system Coliseu Speed Force v3 (Coliseu Blue).
///
/// Light e Dark mode completos usando os tokens de AppColors e AppTypography.
/// Todos os widgets M3 (NavigationBar, Card, Input, Button, etc.) estilizados.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

abstract final class AppTheme {
  // ═════════════════════════════════════════════════════════════════════════
  // LIGHT
  // ═════════════════════════════════════════════════════════════════════════
  static ThemeData get light => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorSchemeSeed: AppColors.primary,

    // ── Scaffold ───────────────────────────────────────────────────────
    scaffoldBackgroundColor: AppColors.surfaceSecondary,

    // ── Typography ────────────────────────────────────────────────────
    textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme).copyWith(
      displayLarge:  AppTypography.displayLarge.copyWith(color: AppColors.textPrimary),
      displayMedium: AppTypography.displayMedium.copyWith(color: AppColors.textPrimary),
      headlineLarge: AppTypography.headingLarge.copyWith(color: AppColors.textPrimary),
      headlineMedium: AppTypography.headingMedium.copyWith(color: AppColors.textPrimary),
      headlineSmall: AppTypography.headingSmall.copyWith(color: AppColors.textPrimary),
      titleLarge:    AppTypography.headingLarge.copyWith(color: AppColors.textPrimary),
      titleMedium:   AppTypography.label.copyWith(color: AppColors.textPrimary),
      titleSmall:    AppTypography.caption.copyWith(color: AppColors.textSecondary),
      bodyLarge:     AppTypography.body.copyWith(color: AppColors.textPrimary),
      bodyMedium:    AppTypography.body.copyWith(color: AppColors.textPrimary),
      bodySmall:     AppTypography.caption.copyWith(color: AppColors.textSecondary),
      labelLarge:    AppTypography.button.copyWith(color: AppColors.textPrimary),
      labelMedium:   AppTypography.label.copyWith(color: AppColors.textSecondary),
      labelSmall:    AppTypography.badge.copyWith(color: AppColors.textTertiary),
    ),

    // ── AppBar ────────────────────────────────────────────────────────
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 1,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: AppTypography.headingLarge.copyWith(
        color: AppColors.textPrimary,
      ),
      iconTheme: const IconThemeData(color: AppColors.textSecondary, size: 24),
    ),

    // ── NavigationBar (Bottom) ────────────────────────────────────────
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      elevation: 0,
      height: 72,
      indicatorColor: AppColors.primary.withOpacity(0.12),
      surfaceTintColor: Colors.transparent,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppTypography.badge.copyWith(
            color: AppColors.primary,
            fontWeight: FontWeight.w700,
          );
        }
        return AppTypography.badge.copyWith(
          color: AppColors.textTertiary,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: AppColors.primary, size: 24);
        }
        return const IconThemeData(color: AppColors.textTertiary, size: 24);
      }),
    ),

    // ── Card ──────────────────────────────────────────────────────────
    cardTheme: CardThemeData(
      color: AppColors.surfaceElevated,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.cardRadius,
        side: const BorderSide(color: AppColors.border, width: 1),
      ),
      margin: EdgeInsets.zero,
    ),

    // ── Divider ───────────────────────────────────────────────────────
    dividerTheme: const DividerThemeData(
      color: AppColors.divider,
      thickness: 1,
      space: 1,
    ),

    // ── Input ─────────────────────────────────────────────────────────
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.inputFill,
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
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: AppRadius.inputRadius,
        borderSide: const BorderSide(color: AppColors.error, width: 1),
      ),
      hintStyle: AppTypography.body.copyWith(color: AppColors.textTertiary),
      labelStyle: AppTypography.label.copyWith(color: AppColors.textSecondary),
      floatingLabelStyle: AppTypography.label.copyWith(color: AppColors.primary),
      errorStyle: AppTypography.caption.copyWith(color: AppColors.error),
    ),

    // ── ElevatedButton (primary CTA) ─────────────────────────────────
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

    // ── FilledButton ─────────────────────────────────────────────────
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.buttonRadius),
        textStyle: AppTypography.button,
      ),
    ),

    // ── OutlinedButton ───────────────────────────────────────────────
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        minimumSize: const Size(0, 52),
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.buttonRadius),
        textStyle: AppTypography.button,
      ),
    ),

    // ── TextButton ───────────────────────────────────────────────────
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        textStyle: AppTypography.button,
      ),
    ),

    // ── Chip ──────────────────────────────────────────────────────────
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surfaceMuted,
      selectedColor: AppColors.primary.withOpacity(0.12),
      labelStyle: AppTypography.badge.copyWith(color: AppColors.textPrimary),
      secondaryLabelStyle: AppTypography.badge.copyWith(color: AppColors.primary),
      shape: RoundedRectangleBorder(borderRadius: AppRadius.chipRadius),
      side: BorderSide.none,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    ),

    // ── BottomSheet ───────────────────────────────────────────────────
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      modalBackgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.sheetRadius),
      showDragHandle: true,
      dragHandleColor: AppColors.border,
    ),

    // ── SnackBar ──────────────────────────────────────────────────────
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.cardRadius),
      insetPadding: const EdgeInsets.all(AppSpacing.lg),
    ),

    // ── FloatingActionButton ──────────────────────────────────────────
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: AppColors.primary,
      foregroundColor: AppColors.onPrimary,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),

    // ── Dialog ────────────────────────────────────────────────────────
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.cardRadius),
      elevation: 4,
      titleTextStyle: AppTypography.headingMedium.copyWith(color: AppColors.textPrimary),
      contentTextStyle: AppTypography.body.copyWith(color: AppColors.textSecondary),
    ),

    // ── ListTile ──────────────────────────────────────────────────────
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      titleTextStyle: AppTypography.bodyBold.copyWith(color: AppColors.textPrimary),
      subtitleTextStyle: AppTypography.caption.copyWith(color: AppColors.textSecondary),
      iconColor: AppColors.textSecondary,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.cardRadius),
    ),

    // ── TabBar ────────────────────────────────────────────────────────
    tabBarTheme: TabBarThemeData(
      labelColor: AppColors.primary,
      unselectedLabelColor: AppColors.textTertiary,
      labelStyle: AppTypography.button,
      unselectedLabelStyle: AppTypography.button,
      indicatorSize: TabBarIndicatorSize.label,
    ),

    // ── Icon ──────────────────────────────────────────────────────────
    iconTheme: const IconThemeData(color: AppColors.textSecondary, size: 24),

    // ── Switch / Checkbox ─────────────────────────────────────────────
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return AppColors.primary;
        return AppColors.textTertiary;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppColors.primary.withOpacity(0.3);
        }
        return AppColors.border;
      }),
    ),
  );

  // ═════════════════════════════════════════════════════════════════════════
  // DARK
  // ═════════════════════════════════════════════════════════════════════════
  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorSchemeSeed: AppColors.primaryDM,

    scaffoldBackgroundColor: AppColors.surfaceDM,

    textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme).copyWith(
      displayLarge:  AppTypography.displayLarge.copyWith(color: AppColors.textPrimaryDM),
      displayMedium: AppTypography.displayMedium.copyWith(color: AppColors.textPrimaryDM),
      headlineLarge: AppTypography.headingLarge.copyWith(color: AppColors.textPrimaryDM),
      headlineMedium: AppTypography.headingMedium.copyWith(color: AppColors.textPrimaryDM),
      headlineSmall: AppTypography.headingSmall.copyWith(color: AppColors.textPrimaryDM),
      titleLarge:    AppTypography.headingLarge.copyWith(color: AppColors.textPrimaryDM),
      titleMedium:   AppTypography.label.copyWith(color: AppColors.textPrimaryDM),
      titleSmall:    AppTypography.caption.copyWith(color: AppColors.textSecondaryDM),
      bodyLarge:     AppTypography.body.copyWith(color: AppColors.textPrimaryDM),
      bodyMedium:    AppTypography.body.copyWith(color: AppColors.textPrimaryDM),
      bodySmall:     AppTypography.caption.copyWith(color: AppColors.textSecondaryDM),
      labelLarge:    AppTypography.button.copyWith(color: AppColors.textPrimaryDM),
      labelMedium:   AppTypography.label.copyWith(color: AppColors.textSecondaryDM),
      labelSmall:    AppTypography.badge.copyWith(color: AppColors.textTertiaryDM),
    ),

    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.surfaceDM,
      foregroundColor: AppColors.textPrimaryDM,
      elevation: 0,
      scrolledUnderElevation: 1,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: AppTypography.headingLarge.copyWith(
        color: AppColors.textPrimaryDM,
      ),
      iconTheme: const IconThemeData(color: AppColors.textSecondaryDM, size: 24),
    ),

    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surfaceSecondaryDM,
      elevation: 0,
      height: 72,
      indicatorColor: AppColors.primaryDM.withOpacity(0.15),
      surfaceTintColor: Colors.transparent,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppTypography.badge.copyWith(
            color: AppColors.primaryDM,
            fontWeight: FontWeight.w700,
          );
        }
        return AppTypography.badge.copyWith(
          color: AppColors.textTertiaryDM,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: AppColors.primaryDM, size: 24);
        }
        return const IconThemeData(color: AppColors.textTertiaryDM, size: 24);
      }),
    ),

    cardTheme: CardThemeData(
      color: AppColors.surfaceElevatedDM,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.cardRadius,
        side: const BorderSide(color: AppColors.borderDark, width: 1),
      ),
      margin: EdgeInsets.zero,
    ),

    dividerTheme: const DividerThemeData(
      color: AppColors.dividerDark,
      thickness: 1,
      space: 1,
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceMutedDM,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: AppRadius.inputRadius,
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: AppRadius.inputRadius,
        borderSide: const BorderSide(color: AppColors.borderDark, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: AppRadius.inputRadius,
        borderSide: const BorderSide(color: AppColors.primaryDM, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: AppRadius.inputRadius,
        borderSide: const BorderSide(color: AppColors.errorDM, width: 1),
      ),
      hintStyle: AppTypography.body.copyWith(color: AppColors.textTertiaryDM),
      labelStyle: AppTypography.label.copyWith(color: AppColors.textSecondaryDM),
      floatingLabelStyle: AppTypography.label.copyWith(color: AppColors.primaryDM),
      errorStyle: AppTypography.caption.copyWith(color: AppColors.errorDM),
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primaryDM,
        foregroundColor: AppColors.surfaceDM,
        elevation: 0,
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.buttonRadius),
        textStyle: AppTypography.button,
      ),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primaryDM,
        foregroundColor: AppColors.surfaceDM,
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.buttonRadius),
        textStyle: AppTypography.button,
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primaryDM,
        minimumSize: const Size(0, 52),
        side: const BorderSide(color: AppColors.borderDark),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.buttonRadius),
        textStyle: AppTypography.button,
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primaryDM,
        textStyle: AppTypography.button,
      ),
    ),

    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surfaceMutedDM,
      selectedColor: AppColors.primaryDM.withOpacity(0.15),
      labelStyle: AppTypography.badge.copyWith(color: AppColors.textPrimaryDM),
      secondaryLabelStyle: AppTypography.badge.copyWith(color: AppColors.primaryDM),
      shape: RoundedRectangleBorder(borderRadius: AppRadius.chipRadius),
      side: BorderSide.none,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    ),

    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: AppColors.surfaceSecondaryDM,
      modalBackgroundColor: AppColors.surfaceSecondaryDM,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.sheetRadius),
      showDragHandle: true,
      dragHandleColor: AppColors.borderDark,
    ),

    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.cardRadius),
      insetPadding: const EdgeInsets.all(AppSpacing.lg),
    ),

    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: AppColors.primaryDM,
      foregroundColor: AppColors.surfaceDM,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surfaceSecondaryDM,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.cardRadius),
      elevation: 4,
      titleTextStyle: AppTypography.headingMedium.copyWith(color: AppColors.textPrimaryDM),
      contentTextStyle: AppTypography.body.copyWith(color: AppColors.textSecondaryDM),
    ),

    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      titleTextStyle: AppTypography.bodyBold.copyWith(color: AppColors.textPrimaryDM),
      subtitleTextStyle: AppTypography.caption.copyWith(color: AppColors.textSecondaryDM),
      iconColor: AppColors.textSecondaryDM,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.cardRadius),
    ),

    tabBarTheme: TabBarThemeData(
      labelColor: AppColors.primaryDM,
      unselectedLabelColor: AppColors.textTertiaryDM,
      labelStyle: AppTypography.button,
      unselectedLabelStyle: AppTypography.button,
      indicatorSize: TabBarIndicatorSize.label,
    ),

    iconTheme: const IconThemeData(color: AppColors.textSecondaryDM, size: 24),

    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return AppColors.primaryDM;
        return AppColors.textTertiaryDM;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppColors.primaryDM.withOpacity(0.3);
        }
        return AppColors.borderDark;
      }),
    ),
  );
}

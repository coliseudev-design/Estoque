/// Tokens de cor do sistema de design — Coliseu Speed Force v3.
///
/// Paleta principal: **Coliseu Blue** (#1E5EFF).
/// Superfícies: Slate neutros com fundo levemente azulado (#F5F7FB).
/// WCAG AAA (ratio ≥ 7:1) para pares de texto/fundo críticos.
///
/// Nunca usar cores hardcoded fora deste arquivo.
library;

import 'package:flutter/material.dart';

abstract final class AppColors {
  // ── Marca — Coliseu Speed Orange ──────────────────────────────────────────
  static const Color primary       = Color(0xFFEA580C);   // Speed Orange
  static const Color primaryLight  = Color(0xFFF97316);   // Secondary Orange
  static const Color primaryDark   = Color(0xFFC2410C);
  static const Color onPrimary     = Color(0xFFFFFFFF);

  // Dark mode primary
  static const Color primaryDM       = Color(0xFFFB923C);
  static const Color primaryLightDM  = Color(0xFFFFEDD5);

  // ── Gradientes ───────────────────────────────────────────────────────────
  static const List<Color> primaryGradient = [
    Color(0xFFEA580C),
    Color(0xFFF97316),
  ];
  static const List<Color> heroGradient = [
    Color(0xFFEA580C),
    Color(0xFFC2410C),
  ];
  /// Gradiente premium Blue-Deep → Indigo (tela de cliente redesign).
  static const List<Color> heroGradientPremium = [
    Color(0xFF1E40AF),   // Blue Deep 800
    Color(0xFF3730A3),   // Indigo 700
    Color(0xFF312E81),   // Indigo 900
  ];

  // ── Fundo especial ───────────────────────────────────────────────────────
  /// Fundo geral da tela de clientes — levemente azulado, distinto do branco.
  static const Color bgTinted = Color(0xFFF0F4FF);

  // ── Glassmorphism leve (sem BackdropFilter — zero jank) ──────────────────
  /// Preenchimento do mini-card glass no hero (rgba branco 15%).
  static const Color glassFill   = Color(0x26FFFFFF);
  /// Borda do mini-card glass no hero (rgba branco 25%).
  static const Color glassBorder = Color(0x40FFFFFF);

  // ── Coral / Laranja (redesign) ───────────────────────────────────────────
  static const Color redCoral      = Color(0xFFEF4444);   // Alerta / Vencido
  static const Color redCoralLight = Color(0xFFFEE2E2);
  static const Color orangeSoft    = Color(0xFFF97316);   // Atenção / Rota
  static const Color orangeLight   = Color(0xFFFFF7ED);

  // ── Accent ───────────────────────────────────────────────────────────────
  static const Color accent      = Color(0xFF10B981);     // Emerald
  static const Color accentLight = Color(0xFFD1FAE5);

  // ── Superfícies ──────────────────────────────────────────────────────────
  static const Color surface          = Color(0xFFFFFFFF);
  static const Color surfaceSecondary = Color(0xFFF5F7FB); // Coliseu Background
  static const Color surfaceElevated  = Color(0xFFFFFFFF);
  static const Color surfaceMuted     = Color(0xFFEEF1F7);
  static const Color inputFill        = Color(0xFFF5F7FB);

  // Dark mode
  static const Color surfaceDM          = Color(0xFF0F172A); // Slate 900
  static const Color surfaceSecondaryDM = Color(0xFF1E293B); // Slate 800
  static const Color surfaceElevatedDM  = Color(0xFF1E293B);
  static const Color surfaceMutedDM     = Color(0xFF334155); // Slate 700

  // ── Texto ────────────────────────────────────────────────────────────────
  static const Color textPrimary   = Color(0xFF0F172A);   // Slate 900 — ratio 18:1
  static const Color textSecondary = Color(0xFF475569);   // Slate 600 — ratio 7.5:1
  static const Color textTertiary  = Color(0xFF94A3B8);   // Slate 400
  static const Color textDisabled  = Color(0xFFCBD5E1);   // Slate 300

  // Dark mode
  static const Color textPrimaryDM   = Color(0xFFF1F5F9);
  static const Color textSecondaryDM = Color(0xFF94A3B8);
  static const Color textTertiaryDM  = Color(0xFF64748B);

  // ── Estados semânticos ───────────────────────────────────────────────────
  static const Color success      = Color(0xFF059669);     // Emerald 600
  static const Color successLight = Color(0xFFD1FAE5);
  static const Color successDM    = Color(0xFF34D399);

  static const Color warning      = Color(0xFFD97706);     // Amber 600
  static const Color warningLight = Color(0xFFFEF3C7);
  static const Color warningDM    = Color(0xFFFBBF24);

  static const Color error      = Color(0xFFDC2626);       // Red 600
  static const Color errorLight = Color(0xFFFEE2E2);
  static const Color errorDM    = Color(0xFFF87171);

  static const Color info      = Color(0xFF2563EB);        // Blue 600
  static const Color infoLight = Color(0xFFDBEAFE);
  static const Color infoDM    = Color(0xFF60A5FA);

  // ── Aliases de sync (backward-compat) ────────────────────────────────────
  static const Color syncSuccess       = success;
  static const Color syncSuccessLight  = successLight;
  static const Color syncPending       = warning;
  static const Color syncPendingLight  = warningLight;
  static const Color syncInProgress    = info;
  static const Color syncInProgressLight = infoLight;
  static const Color syncError         = error;
  static const Color syncErrorLight    = errorLight;

  // Dark aliases
  static const Color syncSuccessDark     = successDM;
  static const Color syncPendingDark     = warningDM;
  static const Color syncInProgressDark  = infoDM;
  static const Color syncErrorDark       = errorDM;

  // ── Bordas e divisores ───────────────────────────────────────────────────
  static const Color border     = Color(0xFFE2E8F0);      // Slate 200
  static const Color borderDark = Color(0xFF334155);       // Slate 700
  static const Color divider    = Color(0xFFF1F5F9);       // Slate 100
  static const Color dividerDark = Color(0xFF1E293B);      // Slate 800

  // ── Sombras ──────────────────────────────────────────────────────────────
  static const Color cardShadow = Color(0x0A1E5EFF);      // Azul sutil (brand shadow)
  static const Color elevation1 = Color(0x0D000000);
  static const Color elevation2 = Color(0x14000000);

  // ── Shimmer / Skeleton ───────────────────────────────────────────────────
  static const Color shimmerBase      = Color(0xFFE2E8F0);
  static const Color shimmerHighlight = Color(0xFFF8FAFC);
  static const Color shimmerBaseDM      = Color(0xFF334155);
  static const Color shimmerHighlightDM = Color(0xFF475569);

  // ── Aliases de conveniência (backward-compat) ───────────────────────────
  static const Color actionPrimary     = primary;
  static const Color actionPrimaryText = onPrimary;
  static const Color actionPrimaryDark = primaryDM;
  static const Color backgroundPrimary   = surface;
  static const Color backgroundSecondary = surfaceSecondary;
  static const Color surfacePrimary   = surface;
  static const Color surfacePrimaryDark   = surfaceDM;
  static const Color surfaceSecondaryDark = surfaceSecondaryDM;
  static const Color surfaceCard      = surface;
  static const Color surfaceCardDark  = surfaceElevatedDM;
  static const Color textPrimaryDark   = textPrimaryDM;
  static const Color textSecondaryDark = textSecondaryDM;
}

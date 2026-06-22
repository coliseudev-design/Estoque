/// Tokens de espaçamento e raio de borda — Coliseu Sales Force.
///
/// Uso consistente garante ritmo visual uniforme em todas as telas.
/// Nunca use valores mágicos; sempre use estas constantes.
library;

import 'package:flutter/material.dart';

abstract final class AppSpacing {
  // ── Espaçamento ──────────────────────────────────────────────────────────
  static const double xs  = 4;
  static const double sm  = 8;
  static const double md  = 12;
  static const double lg  = 16;
  static const double xl  = 24;
  static const double xxl = 32;

  // ── Padding de seção ─────────────────────────────────────────────────────
  static const EdgeInsets screenPadding    = EdgeInsets.all(lg);
  static const EdgeInsets screenPaddingH   = EdgeInsets.symmetric(horizontal: lg);
  static const EdgeInsets cardPadding      = EdgeInsets.all(lg);
  static const EdgeInsets cardPaddingSmall = EdgeInsets.all(md);
  static const EdgeInsets sectionGap       = EdgeInsets.only(bottom: xl);
}

abstract final class AppRadius {
  static const double sm  = 8;
  static const double md  = 12;
  static const double lg  = 16;
  static const double xl  = 24;
  static const double pill = 999;

  // BorderRadius prontos para uso
  static final BorderRadius cardRadius    = BorderRadius.circular(md);
  static final BorderRadius chipRadius    = BorderRadius.circular(pill);
  static final BorderRadius buttonRadius  = BorderRadius.circular(md);
  static final BorderRadius inputRadius   = BorderRadius.circular(md);
  static final BorderRadius sheetRadius   = BorderRadius.vertical(top: Radius.circular(xl));
  static final BorderRadius premiumCard   = BorderRadius.circular(24);
}

/// Sombras padronizadas (soft shadows) usadas pelo redesign premium.
abstract final class AppShadow {
  /// Sombra leve para cards brancos (evita linhas divisórias).
  static const List<BoxShadow> card = [
    BoxShadow(
      color: Color(0x0F1E40AF),  // Blue-brand, 6% opacidade
      blurRadius: 16,
      offset: Offset(0, 4),
    ),
    BoxShadow(
      color: Color(0x08000000),  // Neutro, 3%
      blurRadius: 6,
      offset: Offset(0, 2),
    ),
  ];

  /// Sombra para o hero card (mais elevado).
  static const List<BoxShadow> hero = [
    BoxShadow(
      color: Color(0x281E40AF),
      blurRadius: 32,
      offset: Offset(0, 12),
    ),
  ];
}

/// Escala tipográfica — Coliseu Speed Force v2.
///
/// Fonte primária: Inter (via google_fonts, cache offline).
/// Numérica: JetBrains Mono para preços e quantidades.
/// Tamanho mínimo de corpo: 15sp (field-optimized).
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

abstract final class AppTypography {
  // ── Helper para gerar TextStyles com Inter ──────────────────────────────
  static TextStyle _inter({
    double fontSize = 16,
    FontWeight fontWeight = FontWeight.w400,
    double letterSpacing = 0,
    double height = 1.5,
  }) => GoogleFonts.inter(
    fontSize: fontSize,
    fontWeight: fontWeight,
    letterSpacing: letterSpacing,
    height: height,
  );

  static TextStyle _mono({
    double fontSize = 16,
    FontWeight fontWeight = FontWeight.w700,
    double letterSpacing = 0,
    double height = 1.3,
  }) => GoogleFonts.jetBrainsMono(
    fontSize: fontSize,
    fontWeight: fontWeight,
    letterSpacing: letterSpacing,
    height: height,
  );

  // ── Display ─────────────────────────────────────────────────────────────
  /// Números hero (dashboard, totais grandes)
  static final TextStyle displayLarge = _inter(
    fontSize: 32,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.5,
    height: 1.2,
  );

  /// Títulos de tela / seção
  static final TextStyle displayMedium = _inter(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
    height: 1.3,
  );

  // ── Headings ────────────────────────────────────────────────────────────
  /// Títulos de seção dentro de página
  static final TextStyle headingLarge = _inter(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    height: 1.3,
  );

  /// Subtítulos / cabeçalhos de card
  static final TextStyle headingMedium = _inter(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
    height: 1.4,
  );

  /// Labels, cabeçalhos menores
  static final TextStyle headingSmall = _inter(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
    height: 1.3,
  );

  // ── Body ────────────────────────────────────────────────────────────────
  /// Texto padrão de corpo
  static final TextStyle body = _inter(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.1,
    height: 1.5,
  );

  /// Corpo negrito
  static final TextStyle bodyBold = _inter(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
    height: 1.5,
  );

  /// Texto menor para metadados, timestamps
  static final TextStyle caption = _inter(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.2,
    height: 1.4,
  );

  /// Texto de badge / chip
  static final TextStyle badge = _inter(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.3,
    height: 1.2,
  );

  /// Label de campo de formulário
  static final TextStyle label = _inter(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.1,
    height: 1.3,
  );

  /// Label de botão
  static final TextStyle button = _inter(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.3,
    height: 1.2,
  );

  // ── Numéricos (mono) ────────────────────────────────────────────────────
  /// Preço grande em destaque
  static final TextStyle priceLarge = _mono(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    height: 1.2,
  );

  /// Preço em linha de lista
  static final TextStyle priceNormal = _mono(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  /// Quantidade / estoque
  static final TextStyle quantity = _mono(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.3,
  );

  /// Código de produto
  static final TextStyle productCode = _mono(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.5,
    height: 1.2,
  );

  // ── Aliases Material Design (backward-compat) ───────────────────────────
  static final TextStyle sectionTitle   = headingLarge;
  static final TextStyle cardTitle      = headingMedium;
  static final TextStyle fieldLabel     = label;
  static final TextStyle headlineLarge  = displayMedium;
  static final TextStyle headlineMedium = headingMedium;
  static final TextStyle titleMedium    = label;
  static final TextStyle bodyLarge      = body;
  static final TextStyle bodyMedium     = body;
  static final TextStyle bodySmall      = caption;
}

library;

import 'package:flutter/material.dart';

abstract final class AppColors {
  // ── Marca Base (Coliseu Blue) ───────────
  static const Color primary       = Color(0xFF2A7FC0);   // Coliseu Blue
  static const Color primaryDark   = Color(0xFF0F3A70);
  static const Color onPrimary     = Color(0xFFFFFFFF);
  
  static const Color accent        = Color(0xFF0F3A70);   // Dark Blue Secondary
  static const Color accentDark    = Color(0xFF0B2950);
  static const Color onAccent      = Color(0xFFFFFFFF);

  // ── Superfícies Light Mode (Coliseu Padrão) ────────────────────────────
  static const Color surface          = Color(0xFFF9FAFB); // Fundo App
  static const Color surfaceElevated  = Color(0xFFFFFFFF); // Fundo Cards
  static const Color surfaceMuted     = Color(0xFFF1F5F9); // Inputs/Fundo Seçōes

  // ── Textos ──────────────────────────────────────────────────────────────
  static const Color textPrimary   = Color(0xFF3D3D3D);   // Grafite
  static const Color textSecondary = Color(0xFF64748B);   // Cinza Médio
  static const Color textTertiary  = Color(0xFF94A3B8);   // Cinza Claro
  
  // ── Estados Semânticos ──────────────────────────────────────────────────
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error   = Color(0xFFEF4444);

  // ── Bordas ──────────────────────────────────────────────────────────────
  static const Color border     = Color(0xFFE2E8F0);
  static const Color divider    = Color(0xFFCBD5E1);
}

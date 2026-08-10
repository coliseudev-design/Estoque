library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

abstract final class AppTypography {
  static const _baseFont = GoogleFonts.inter;

  static final TextStyle headingLarge = _baseFont(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
  );

  static final TextStyle headingMedium = _baseFont(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
  );

  static final TextStyle bodyBold = _baseFont(
    fontSize: 16,
    fontWeight: FontWeight.w600,
  );

  static final TextStyle body = _baseFont(
    fontSize: 16,
    fontWeight: FontWeight.w400,
  );

  static final TextStyle label = _baseFont(
    fontSize: 14,
    fontWeight: FontWeight.w500,
  );

  static final TextStyle caption = _baseFont(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.2,
  );

  static final TextStyle button = _baseFont(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.5,
  );
}

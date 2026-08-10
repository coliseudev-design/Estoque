library;

import 'package:flutter/material.dart';

/// Define abstrações consistentes de espaçamento e bordas
abstract final class AppSpacing {
  static const double xs  = 4.0;
  static const double sm  = 8.0;
  static const double md  = 16.0;
  static const double lg  = 24.0;
  static const double xl  = 32.0;
  static const double xxl = 48.0;
}

abstract final class AppRadius {
  static final BorderRadius buttonRadius = BorderRadius.circular(12);
  static final BorderRadius inputRadius  = BorderRadius.circular(12);
  static final BorderRadius cardRadius   = BorderRadius.circular(16);
  static final BorderRadius sheetRadius  = const BorderRadius.vertical(top: Radius.circular(24));
}

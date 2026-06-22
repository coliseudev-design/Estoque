/// ColiseuCard — Container padronizado para agrupar conteúdo.
///
/// Variants: flat (sem sombra), elevated (sombra brand), outlined (borda).
/// Raio: 16px. Sombra usa AppColors.cardShadow (tint azul sutil).
library;

import 'package:flutter/material.dart';
import '../core/design/app_colors.dart';

enum ColiseuCardVariant { flat, elevated, outlined }

class ColiseuCard extends StatelessWidget {
  final Widget child;
  final ColiseuCardVariant variant;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  const ColiseuCard({
    super.key,
    required this.child,
    this.variant = ColiseuCardVariant.flat,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final decoration = BoxDecoration(
      color: isDark ? AppColors.surfaceElevatedDM : AppColors.surfaceElevated,
      borderRadius: BorderRadius.circular(16),
      border: variant == ColiseuCardVariant.outlined
          ? Border.all(color: isDark ? AppColors.borderDark : AppColors.border)
          : null,
      boxShadow: variant == ColiseuCardVariant.elevated
          ? [
              BoxShadow(
                color: AppColors.cardShadow,
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ]
          : null,
    );

    final content = Padding(padding: padding, child: child);

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        child: Container(decoration: decoration, child: content),
      );
    }
    return Container(decoration: decoration, child: content);
  }
}

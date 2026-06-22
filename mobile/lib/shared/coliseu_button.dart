/// ColiseuButton — Botões padronizados com estados visuais claros.
///
/// Variants: primary (filled), secondary (tonal), outline.
/// Tamanho mínimo: 48px (touch-friendly para campo).
/// Bordas: 12px. Sombra suave no primary.
library;

import 'package:flutter/material.dart';
import '../core/design/app_colors.dart';
import '../core/design/app_typography.dart';

enum ColiseuButtonVariant { primary, secondary, outline }

class ColiseuButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final ColiseuButtonVariant variant;
  final bool loading;
  final bool expanded;

  const ColiseuButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.variant = ColiseuButtonVariant.primary,
    this.loading = false,
    this.expanded = false,
  });

  /// Factory rápida para botão primário com ícone.
  const ColiseuButton.primary({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.loading = false,
    this.expanded = true,
  }) : variant = ColiseuButtonVariant.primary;

  /// Factory rápida para botão secundário.
  const ColiseuButton.secondary({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.loading = false,
    this.expanded = true,
  }) : variant = ColiseuButtonVariant.secondary;

  /// Factory rápida para botão outline.
  const ColiseuButton.outline({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.loading = false,
    this.expanded = false,
  }) : variant = ColiseuButtonVariant.outline;

  @override
  Widget build(BuildContext context) {
    final child = _buildChild();

    Widget button;
    switch (variant) {
      case ColiseuButtonVariant.primary:
        button = FilledButton(
          onPressed: loading ? null : onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.onPrimary,
            disabledBackgroundColor: AppColors.primary.withOpacity(0.5),
            minimumSize: const Size(0, 48),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 2,
            shadowColor: AppColors.cardShadow,
          ),
          child: child,
        );
      case ColiseuButtonVariant.secondary:
        button = FilledButton.tonal(
          onPressed: loading ? null : onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary.withOpacity(0.1),
            foregroundColor: AppColors.primary,
            minimumSize: const Size(0, 48),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 0,
          ),
          child: child,
        );
      case ColiseuButtonVariant.outline:
        button = OutlinedButton(
          onPressed: loading ? null : onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            minimumSize: const Size(0, 48),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            side: const BorderSide(color: AppColors.border, width: 1.5),
          ),
          child: child,
        );
    }

    return expanded ? SizedBox(width: double.infinity, child: button) : button;
  }

  Widget _buildChild() {
    if (loading) {
      return SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: variant == ColiseuButtonVariant.primary
              ? AppColors.onPrimary
              : AppColors.primary,
        ),
      );
    }

    if (icon != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Text(label, style: AppTypography.button),
        ],
      );
    }

    return Text(label, style: AppTypography.button);
  }
}

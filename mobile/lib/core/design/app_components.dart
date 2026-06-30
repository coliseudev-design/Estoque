/// Componentes compartilhados — Coliseu Speed Force v2.
///
/// Widgets reutilizáveis que formam o vocabulário visual do app.
/// Todos usam tokens de design (AppColors, AppTypography, AppSpacing).
library;

import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AppCard — Card wrapper consistente
// ─────────────────────────────────────────────────────────────────────────────

/// Card padronizado com radius, elevation e padding consistentes.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final Color? color;

  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = color ?? (isDark ? AppColors.surfaceElevatedDM : AppColors.surfaceElevated);

    return Material(
      color: cardColor,
      borderRadius: AppRadius.cardRadius,
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.cardRadius,
        child: Container(
          padding: padding ?? AppSpacing.cardPadding,
          decoration: BoxDecoration(
            borderRadius: AppRadius.cardRadius,
            border: Border.all(
              color: isDark ? AppColors.borderDark : AppColors.border,
              width: 1,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// StatusBadge — Badge de status em pill
// ─────────────────────────────────────────────────────────────────────────────

enum BadgeVariant { success, warning, error, info, neutral }

/// Badge em formato pill para indicar status de sync, pedido, estoque.
class StatusBadge extends StatelessWidget {
  final String label;
  final BadgeVariant variant;
  final IconData? icon;

  const StatusBadge({
    super.key,
    required this.label,
    required this.variant,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final (Color bg, Color fg) = switch (variant) {
      BadgeVariant.success => (
        isDark ? AppColors.success.withOpacity(0.2) : AppColors.successLight,
        isDark ? AppColors.successDM : AppColors.success,
      ),
      BadgeVariant.warning => (
        isDark ? AppColors.warning.withOpacity(0.2) : AppColors.warningLight,
        isDark ? AppColors.warningDM : AppColors.warning,
      ),
      BadgeVariant.error => (
        isDark ? AppColors.error.withOpacity(0.2) : AppColors.errorLight,
        isDark ? AppColors.errorDM : AppColors.error,
      ),
      BadgeVariant.info => (
        isDark ? AppColors.info.withOpacity(0.2) : AppColors.infoLight,
        isDark ? AppColors.infoDM : AppColors.info,
      ),
      BadgeVariant.neutral => (
        isDark ? AppColors.surfaceMutedDM : AppColors.surfaceMuted,
        isDark ? AppColors.textSecondaryDM : AppColors.textSecondary,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadius.chipRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              style: AppTypography.badge.copyWith(color: fg),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SectionHeader — Cabeçalho de seção com ação opcional
// ─────────────────────────────────────────────────────────────────────────────

/// Cabeçalho de seção padrão (ex: "Últimos Pedidos" com "Ver todos →").
class SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              title,
              style: AppTypography.headingSmall.copyWith(
                color: isDark ? AppColors.textSecondaryDM : AppColors.textSecondary,
                letterSpacing: 0.5,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (actionLabel != null)
            GestureDetector(
              onTap: onAction,
              child: Text(
                actionLabel!,
                style: AppTypography.caption.copyWith(
                  color: isDark ? AppColors.primaryDM : AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AppSearchBar — Barra de busca arredondada
// ─────────────────────────────────────────────────────────────────────────────

/// Search bar estilizada com ícone de busca, clear button e hint.
class AppSearchBar extends StatelessWidget {
  final TextEditingController? controller;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onClear;
  final Widget? trailing;

  const AppSearchBar({
    super.key,
    this.controller,
    this.hintText = 'Buscar...',
    this.onChanged,
    this.onClear,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceMutedDM : AppColors.surfaceMuted,
        borderRadius: AppRadius.inputRadius,
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: AppTypography.body.copyWith(
          color: isDark ? AppColors.textPrimaryDM : AppColors.textPrimary,
        ),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: AppTypography.body.copyWith(
            color: isDark ? AppColors.textTertiaryDM : AppColors.textTertiary,
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            color: isDark ? AppColors.textTertiaryDM : AppColors.textTertiary,
            size: 22,
          ),
          suffixIcon: trailing ?? (
            controller != null && controller!.text.isNotEmpty
              ? IconButton(
                  icon: Icon(
                    Icons.close_rounded,
                    color: isDark ? AppColors.textTertiaryDM : AppColors.textTertiary,
                    size: 20,
                  ),
                  onPressed: () {
                    controller?.clear();
                    onClear?.call();
                  },
                )
              : null
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AppEmptyState — Estado vazio ilustrativo
// ─────────────────────────────────────────────────────────────────────────────

/// Widget padrão para estados vazios (nenhum item, nenhum pedido, etc.).
class AppEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: AppSpacing.screenPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceMutedDM : AppColors.surfaceMuted,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 36,
                color: isDark ? AppColors.textTertiaryDM : AppColors.textTertiary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTypography.headingMedium.copyWith(
                color: isDark ? AppColors.textPrimaryDM : AppColors.textPrimary,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: AppTypography.body.copyWith(
                  color: isDark ? AppColors.textSecondaryDM : AppColors.textSecondary,
                ),
              ),
            ],
            if (actionLabel != null) ...[
              const SizedBox(height: AppSpacing.xl),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.add_rounded, size: 20),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// KpiCard — Card para exibição de métricas
// ─────────────────────────────────────────────────────────────────────────────

/// Card de KPI: ícone + label + valor numérico grande.
class KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color iconColor;

  const KpiCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(isDark ? 0.2 : 0.1),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(icon, size: 20, color: iconColor),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 22,
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: AppTypography.headingMedium.copyWith(
                  color: isDark ? AppColors.textPrimaryDM : AppColors.textPrimary,
                ),
                maxLines: 1,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: AppTypography.caption.copyWith(
              color: isDark ? AppColors.textSecondaryDM : AppColors.textSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

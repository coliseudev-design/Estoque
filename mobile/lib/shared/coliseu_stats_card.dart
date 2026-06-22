/// ColiseuStatsCard — KPI card para dashboard comercial.
///
/// Inspirado em Salesforce/Stripe: ícone, valor destacado, label, subtítulo
/// opcional e indicador de tendência (up/down/neutral).
/// Sombra brand-tinted usando AppColors.cardShadow.
library;

import 'package:flutter/material.dart';
import '../core/design/app_colors.dart';
import '../core/design/app_typography.dart';

enum StatsTrend { up, down, neutral }

class ColiseuStatsCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? subtitle;
  final Color? iconColor;
  final Color? iconBackground;
  final StatsTrend? trend;
  final String? trendLabel;

  const ColiseuStatsCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.subtitle,
    this.iconColor,
    this.iconBackground,
    this.trend,
    this.trendLabel,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final effectiveIconColor = iconColor ?? AppColors.primary;
    final effectiveIconBg = iconBackground ?? effectiveIconColor.withOpacity(0.1);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceElevatedDM : AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppColors.borderDark : AppColors.border,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.cardShadow,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon + trend
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: effectiveIconBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: effectiveIconColor),
              ),
              const Spacer(),
              if (trend != null) _buildTrendBadge(),
            ],
          ),
          const SizedBox(height: 10),

          // Value
          Text(
            value,
            style: AppTypography.headingLarge.copyWith(
              color: isDark ? AppColors.textPrimaryDM : AppColors.textPrimary,
              fontSize: 20,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),

          // Label
          Text(
            label,
            style: AppTypography.caption.copyWith(
              color: isDark ? AppColors.textSecondaryDM : AppColors.textSecondary,
              fontSize: 11,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),

          // Subtitle
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: AppTypography.badge.copyWith(
                color: AppColors.textTertiary,
                fontSize: 10,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTrendBadge() {
    final isUp = trend == StatsTrend.up;
    final isDown = trend == StatsTrend.down;
    final color = isUp
        ? AppColors.success
        : isDown
            ? AppColors.error
            : AppColors.textTertiary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isUp ? Icons.trending_up : isDown ? Icons.trending_down : Icons.trending_flat,
            size: 12,
            color: color,
          ),
          if (trendLabel != null) ...[
            const SizedBox(width: 2),
            Text(
              trendLabel!,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color),
            ),
          ],
        ],
      ),
    );
  }
}

/// ColiseuProductCard — Card premium para catálogo e seletor de pedido.
///
/// Exibe: código, nome, preço, estoque, marca.
/// Quick-add: botão "+" para adicionar ao pedido (1 tap).
/// Sem estoque: visual esmaecido com badge "Sem Estoque".
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/design/app_colors.dart';
import '../core/design/app_typography.dart';

class ColiseuProductCard extends StatelessWidget {
  final String code;
  final String name;
  final double price;
  final double stock;
  final String? brand;
  final String? category;
  final String? reference;
  final String? unit;
  final VoidCallback? onTap;
  final VoidCallback? onAdd;
  final bool isFavorite;
  final VoidCallback? onFavorite;
  final bool isLocalBranch;

  static final _currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  const ColiseuProductCard({
    super.key,
    required this.code,
    required this.name,
    required this.price,
    required this.stock,
    this.brand,
    this.category,
    this.reference,
    this.unit,
    this.onTap,
    this.onAdd,
    this.isFavorite = false,
    this.onFavorite,
    this.isLocalBranch = false,
  });

  bool get isInStock => stock > 0;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceElevatedDM : AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? AppColors.borderDark : AppColors.border,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            // Código (badge)
            Container(
              width: 52,
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Center(
                child: Text(
                  code,
                  style: AppTypography.badge.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(width: 10),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    name,
                    style: AppTypography.body.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: isInStock
                          ? (isDark ? AppColors.textPrimaryDM : AppColors.textPrimary)
                          : AppColors.textTertiary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        isInStock
                            ? 'Est: ${stock.toStringAsFixed(0)} ${unit ?? 'un'}'
                            : 'Sem Estoque',
                        style: TextStyle(
                          fontSize: 11,
                          color: isInStock ? AppColors.textSecondary : AppColors.error,
                          fontWeight: isInStock ? FontWeight.w400 : FontWeight.w600,
                        ),
                      ),
                      if (isLocalBranch) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Sua Filial',
                            style: TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (category != null && category!.isNotEmpty) ...[
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Cat: $category',
                              style: TextStyle(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (brand != null && brand!.isNotEmpty) ...[
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppColors.info.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Marca: $brand',
                              style: TextStyle(fontSize: 10, color: AppColors.info, fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            // Preço
            SizedBox(
              width: 80,
              child: Text(
                _currency.format(price),
                style: AppTypography.priceNormal.copyWith(
                  fontSize: 13,
                  color: isInStock
                      ? (isDark ? AppColors.textPrimaryDM : AppColors.textPrimary)
                      : AppColors.textTertiary,
                ),
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // Favorite star
            if (onFavorite != null) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onFavorite,
                child: Icon(
                  isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: 22,
                  color: isFavorite ? AppColors.warning : AppColors.textTertiary,
                ),
              ),
            ],

            // Quick add
            if (onAdd != null) ...[
              const SizedBox(width: 8),
              SizedBox(
                width: 36,
                height: 36,
                child: IconButton.filled(
                  onPressed: isInStock ? onAdd : null,
                  icon: const Icon(Icons.add, size: 18),
                  style: IconButton.styleFrom(
                    backgroundColor: isInStock ? AppColors.primary : AppColors.border,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

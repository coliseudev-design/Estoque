/// DiscountService — Lógica centralizada de validação e cálculo de descontos.
///
/// Regras de negócio respeitadas (em ordem de precedência):
/// 1. Desconto do produto   (Product.maxDiscount) — por item
/// 2. Desconto do vendedor  (Seller.maxDiscount)  — global da sessão
/// 3. Preço mínimo          (Product.priceMin)    — piso absoluto de preço
/// 4. Preço de custo        (Product.priceCost)   — nunca vender abaixo do custo
///
/// Suporta dois modos de entrada:
/// - Percentual (0–100%) → converte para % de desconto
/// - Valor fixo (R$)     → converte para % internamente
///
/// Rule-06 Clean Architecture: toda lógica de desconto centralizada aqui.
/// CartNotifier e CartScreen não calculam limites — apenas chamam este service.
library;

import '../repositories/models/models.dart';
import '../repositories/models/seller.dart';

/// Modo de entrada do desconto.
enum DiscountMode { percent, value }

/// Resultado da validação de um desconto.
class DiscountResult {
  /// Percentual de desconto aplicado (0–100), já clampado dentro dos limites.
  final double percent;

  /// Valor absoluto do desconto por unidade (R$).
  final double valuePerUnit;

  /// Preço unitário final após desconto.
  final double unitPriceAfterDiscount;

  /// Valor total do item (unitPriceAfterDiscount × qty).
  final double totalPrice;

  /// Se o desconto solicitado foi limitado por alguma regra.
  final bool wasClamped;

  /// Motivo do limite, se wasClamped for true.
  final String? clampReason;

  /// Limite máximo de desconto % aplicável a este item.
  final double maxAllowedPercent;

  const DiscountResult({
    required this.percent,
    required this.valuePerUnit,
    required this.unitPriceAfterDiscount,
    required this.totalPrice,
    required this.wasClamped,
    this.clampReason,
    required this.maxAllowedPercent,
  });
}

class DiscountService {
  /// Calcula e valida desconto para um item do carrinho.
  ///
  /// @param product        Produto a ser descontado.
  /// @param quantity       Quantidade no carrinho.
  /// @param inputValue     Valor de entrada (% ou R$).
  /// @param mode           Modo de entrada (percentual ou valor).
  /// @param seller         Vendedor ativo na sessão (para maxDiscount global).
  ///
  /// @returns              [DiscountResult] com percentual e valor clampados.
  DiscountResult calculate({
    required Product product,
    required double quantity,
    required double inputValue,
    required DiscountMode mode,
    Seller? seller,
  }) {
    // ── Calcular % solicitado ────────────────────────────────────────────────
    double requestedPercent;
    if (mode == DiscountMode.percent) {
      requestedPercent = inputValue;
    } else {
      // Desconto em R$ total do item → converte para %
      // inputValue = valor absoluto descontado sobre o subtotal (price × qty)
      final subtotal = product.price * quantity;
      if (subtotal <= 0) return _noDiscount(product, quantity);
      requestedPercent = (inputValue / subtotal * 100).clamp(0.0, 100.0);
    }

    // ── Determinar limite máximo permitido ────────────────────────────────────
    double maxPercent = 100.0;
    String? clampReason;
    bool wasClamped = false;

    // 1. Limite do produto (DESCONTO_MAX do Firebird — 0 = sem limite)
    if (product.maxDiscount != null && product.maxDiscount! > 0 && product.maxDiscount! < maxPercent) {
      maxPercent  = product.maxDiscount!;
      clampReason = 'Desconto máx. do produto: ${maxPercent.toStringAsFixed(0)}%';
    }

    // 2. Limite do vendedor (DESCONTO_MAX do FUNCIONARIOS — 0 = sem limite)
    if (seller?.maxDiscount != null && seller!.maxDiscount! > 0 && seller.maxDiscount! < maxPercent) {
      maxPercent  = seller.maxDiscount!;
      clampReason = 'Limite do vendedor: ${maxPercent.toStringAsFixed(0)}%';
    }

    // 3. Piso do preço mínimo (PRECO_MINIMO) — se > 0
    if (product.priceMin != null && product.priceMin! > 0 && product.price > 0) {
      final maxByPriceMin = ((product.price - product.priceMin!) / product.price * 100)
          .clamp(0.0, 100.0);
      if (maxByPriceMin < maxPercent) {
        maxPercent  = maxByPriceMin;
        clampReason = 'Preço mínimo: ${_fmt(product.priceMin!)}';
      }
    }

    // 4. Piso do preço de custo (PRECO_CUSTO) — piso absoluto de negócio
    if (product.priceCost != null && product.priceCost! > 0 && product.price > 0) {
      final maxByCost = ((product.price - product.priceCost!) / product.price * 100)
          .clamp(0.0, 100.0);
      if (maxByCost < maxPercent) {
        maxPercent  = maxByCost;
        clampReason = 'Preço de custo: ${_fmt(product.priceCost!)} (margem zero)';
      }
    }

    // ── Aplicar clamp ────────────────────────────────────────────────────────
    final appliedPercent = requestedPercent.clamp(0.0, maxPercent);
    if (appliedPercent < requestedPercent) {
      wasClamped = true;
    }

    final unitPrice = product.price * (1 - appliedPercent / 100);
    final vpu       = product.price - unitPrice;
    final total     = unitPrice * quantity;

    return DiscountResult(
      percent:                  appliedPercent,
      valuePerUnit:             vpu,
      unitPriceAfterDiscount:   unitPrice,
      totalPrice:               total,
      wasClamped:               wasClamped,
      clampReason:              wasClamped ? clampReason : null,
      maxAllowedPercent:        maxPercent,
    );
  }

  /// Retorna um [DiscountResult] sem desconto (para preço zero ou sem data).
  DiscountResult _noDiscount(Product product, double quantity) => DiscountResult(
        percent:                0,
        valuePerUnit:           0,
        unitPriceAfterDiscount: product.price,
        totalPrice:             product.price * quantity,
        wasClamped:             false,
        maxAllowedPercent:      0,
      );

  /// Formata valor monetário de forma compacta.
  String _fmt(double v) => 'R\$${v.toStringAsFixed(2).replaceAll('.', ',')}';

  /// Calcula o desconto máximo permitido (%) para exibição no UI.
  ///
  /// Útil para mostrar o limite no campo de entrada antes de digitar.
  double maxAllowed(Product product, Seller? seller) {
    double maxPercent = 100.0;

    if (product.maxDiscount != null && product.maxDiscount! > 0 && product.maxDiscount! < maxPercent) {
      maxPercent = product.maxDiscount!;
    }
    if (seller?.maxDiscount != null && seller!.maxDiscount! > 0 && seller.maxDiscount! < maxPercent) {
      maxPercent = seller.maxDiscount!;
    }
    if (product.priceMin != null && product.priceMin! > 0 && product.price > 0) {
      final maxByPriceMin = ((product.price - product.priceMin!) / product.price * 100)
          .clamp(0.0, 100.0);
      if (maxByPriceMin < maxPercent) maxPercent = maxByPriceMin;
    }

    return maxPercent;
  }

  /// Resume os descontos do carrinho inteiro.
  ///
  /// @returns mapa com gross, totalDiscount, net, avgDiscountPercent, items com alertas
  CartDiscountSummary summarize({
    required List<CartItem> items,
    Seller? seller,
  }) {
    double gross          = 0;
    double totalDiscount  = 0;
    final itemSummaries   = <ItemDiscountSummary>[];

    for (final item in items) {
      final result = calculate(
        product:  item.product,
        quantity: item.quantity,
        inputValue: item.discount,
        mode: DiscountMode.percent,
        seller: seller,
      );
      gross         += item.product.price * item.quantity;
      totalDiscount += result.valuePerUnit * item.quantity;

      itemSummaries.add(ItemDiscountSummary(
        item:             item,
        result:           result,
        grossItemTotal:   item.product.price * item.quantity,
        netItemTotal:     result.totalPrice,
      ));
    }

    final net = gross - totalDiscount;
    final avgPercent = gross > 0 ? totalDiscount / gross * 100 : 0.0;

    return CartDiscountSummary(
      grossTotal:          gross,
      totalDiscountValue:  totalDiscount,
      netTotal:            net,
      avgDiscountPercent:  avgPercent,
      items:               itemSummaries,
    );
  }
}

/// Resumo de desconto de um item específico.
class ItemDiscountSummary {
  final CartItem          item;
  final DiscountResult    result;
  final double            grossItemTotal;
  final double            netItemTotal;

  const ItemDiscountSummary({
    required this.item,
    required this.result,
    required this.grossItemTotal,
    required this.netItemTotal,
  });

  bool get hasDiscount => result.percent > 0;
  bool get hasMarginalAlert => result.wasClamped;
}

/// Resumo completo dos descontos do carrinho.
class CartDiscountSummary {
  final double                    grossTotal;
  final double                    totalDiscountValue;
  final double                    netTotal;
  final double                    avgDiscountPercent;
  final List<ItemDiscountSummary> items;

  const CartDiscountSummary({
    required this.grossTotal,
    required this.totalDiscountValue,
    required this.netTotal,
    required this.avgDiscountPercent,
    required this.items,
  });

  bool get hasDiscounts => totalDiscountValue > 0;
  int get itemsWithAlert => items.where((i) => i.hasMarginalAlert).length;
}

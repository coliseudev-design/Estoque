/// Testes unitários do DiscountService.
///
/// DiscountService é puro (sem I/O, sem DB), ideal para testes rápidos.
/// Regra 10: testa happy paths, edge cases e casos de erro.
///
/// Cobertura:
///   - Desconto percentual dentro do limite → aplicado corretamente
///   - Desconto percentual acima do limite do produto → clampado
///   - Desconto limitado pelo vendedor (seller.maxDiscount)
///   - Desconto limitado pelo preço mínimo (product.priceMin)
///   - Desconto limitado pelo preço de custo (product.priceCost)
///   - Desconto em modo valor (R$) → convertido para %
///   - Produto com preço zero → sem desconto seguro (sem crash ni divisão por zero)
///   - Desconto zero → sem alteração no preço
///   - summarize() com carrinho misto → gross/net corretos
///   - maxAllowed() retorna mínimo entre produto, vendedor e priceMin

library;

import 'package:flutter_test/flutter_test.dart';

import 'package:coliseu_speed/core/services/discount_service.dart';
import 'package:coliseu_speed/core/repositories/models/models.dart';
import 'package:coliseu_speed/core/repositories/models/seller.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Helpers de fixture
// ─────────────────────────────────────────────────────────────────────────────

/// Cria um produto de teste com defaults razoáveis.
Product makeProduct({
  String code = 'P001',
  double price = 100.0,
  double? priceMin,
  double? priceCost,
  double? maxDiscount,
}) =>
    Product(
      code:        code,
      name:        'Produto Teste',
      price:       price,
      stock:       10.0,
      priceMin:    priceMin,
      priceCost:   priceCost,
      maxDiscount: maxDiscount,
    );

/// Cria um seller de teste.
Seller makeSeller({double? maxDiscount}) => Seller(
      id:          'S1',
      name:        'Vendedor Teste',
      maxDiscount: maxDiscount,
    );

/// Cria um CartItem de teste.
CartItem makeCartItem({
  required Product product,
  double quantity = 1.0,
  double discount = 0.0,
}) =>
    CartItem(
      product:  product,
      quantity: quantity,
      discount: discount,
    );

void main() {
  late DiscountService svc;

  setUp(() => svc = DiscountService());

  // ─────────────────────────────────────────────────────────────────────────
  // calculate() — Modo PERCENT
  // ─────────────────────────────────────────────────────────────────────────

  group('calculate() — modo percent', () {
    test('desconto dentro do limite: aplicado sem clamp', () {
      final product = makeProduct(price: 100.0, maxDiscount: 20.0);
      final result  = svc.calculate(
        product:    product,
        quantity:   2,
        inputValue: 10.0,        // 10% — dentro do limite de 20%
        mode:       DiscountMode.percent,
      );

      expect(result.percent,                 10.0);
      expect(result.unitPriceAfterDiscount,  90.0);
      expect(result.totalPrice,              180.0);
      expect(result.wasClamped,              isFalse);
    });

    test('desconto acima do limite do produto: clampado', () {
      final product = makeProduct(price: 100.0, maxDiscount: 15.0);
      final result  = svc.calculate(
        product:    product,
        quantity:   1,
        inputValue: 30.0,        // 30% — acima do limite de 15%
        mode:       DiscountMode.percent,
      );

      expect(result.percent,    closeTo(15.0, 0.01));
      expect(result.wasClamped, isTrue);
      expect(result.clampReason, contains('produto'));
    });

    test('desconto acima do limite do vendedor: clampado pelo vendedor', () {
      final product = makeProduct(price: 100.0);       // sem limite de produto
      final seller  = makeSeller(maxDiscount: 10.0);
      final result  = svc.calculate(
        product:    product,
        quantity:   1,
        inputValue: 25.0,        // 25% — acima do limite de 10% do vendedor
        mode:       DiscountMode.percent,
        seller:     seller,
      );

      expect(result.percent,    closeTo(10.0, 0.01));
      expect(result.wasClamped, isTrue);
      expect(result.clampReason, contains('vendedor'));
    });

    test('desconto limitado pelo priceMin', () {
      // price=100, priceMin=80 → max desconto = 20%
      final product = makeProduct(price: 100.0, priceMin: 80.0);
      final result  = svc.calculate(
        product:    product,
        quantity:   1,
        inputValue: 30.0,        // 30% — acima do limite de 20%
        mode:       DiscountMode.percent,
      );

      expect(result.percent,    closeTo(20.0, 0.01));
      expect(result.wasClamped, isTrue);
      expect(result.clampReason, contains('mínimo'));
    });

    test('desconto limitado pelo priceCost (margem zero)', () {
      // price=100, priceCost=60 → max desconto = 40%
      final product = makeProduct(price: 100.0, priceCost: 60.0);
      final result  = svc.calculate(
        product:    product,
        quantity:   1,
        inputValue: 50.0,        // 50% — acima do limite de 40%
        mode:       DiscountMode.percent,
      );

      expect(result.percent,    closeTo(40.0, 0.01));
      expect(result.wasClamped, isTrue);
      expect(result.clampReason, contains('custo'));
    });

    test('desconto zero: preço inalterado', () {
      final product = makeProduct(price: 100.0);
      final result  = svc.calculate(
        product:    product,
        quantity:   3,
        inputValue: 0.0,
        mode:       DiscountMode.percent,
      );

      expect(result.percent,               0.0);
      expect(result.unitPriceAfterDiscount, 100.0);
      expect(result.totalPrice,             300.0);
      expect(result.wasClamped,             isFalse);
    });

    test('produto com preço zero: retorna sem desconto (sem crash)', () {
      final product = makeProduct(price: 0.0);
      final result  = svc.calculate(
        product:    product,
        quantity:   1,
        inputValue: 50.0,
        mode:       DiscountMode.value,  // R$ sobre preço 0 → sem divisão por zero
      );

      expect(result.percent,   0.0);
      expect(result.totalPrice, 0.0);
      expect(result.wasClamped, isFalse);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // calculate() — Modo VALUE (R$)
  // ─────────────────────────────────────────────────────────────────────────

  group('calculate() — modo value (R\$)', () {
    test('desconto em R\$ convertido para % corretamente', () {
      // R$10 sobre produto de R$100 = 10%
      final product = makeProduct(price: 100.0);
      final result  = svc.calculate(
        product:    product,
        quantity:   2,
        inputValue: 10.0,       // R$ 10
        mode:       DiscountMode.value,
      );

      expect(result.percent,                closeTo(5.0, 0.01));
      expect(result.unitPriceAfterDiscount, closeTo(95.0, 0.01));
      expect(result.totalPrice,             closeTo(190.0, 0.01));
    });

    test('desconto em R\$ acima do limite: clampado', () {
      final product = makeProduct(price: 100.0, maxDiscount: 15.0);
      final result  = svc.calculate(
        product:    product,
        quantity:   1,
        inputValue: 30.0,       // R$ 30 = 30% > limite 15%
        mode:       DiscountMode.value,
      );

      expect(result.percent,    closeTo(15.0, 0.01));
      expect(result.wasClamped, isTrue);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // maxAllowed()
  // ─────────────────────────────────────────────────────────────────────────

  group('maxAllowed()', () {
    test('sem limites: retorna 100%', () {
      final product = makeProduct(price: 100.0);
      expect(svc.maxAllowed(product, null), 100.0);
    });

    test('retorna o menor entre produto e vendedor', () {
      final product = makeProduct(price: 100.0, maxDiscount: 25.0);
      final seller  = makeSeller(maxDiscount: 10.0);
      expect(svc.maxAllowed(product, seller), 10.0);
    });

    test('priceMin mais restritivo que maxDiscount', () {
      // price=100, priceMin=85 → max = 15% < maxDiscount=30%
      final product = makeProduct(price: 100.0, maxDiscount: 30.0, priceMin: 85.0);
      expect(svc.maxAllowed(product, null), closeTo(15.0, 0.01));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // summarize() — Carrinho
  // ─────────────────────────────────────────────────────────────────────────

  group('summarize()', () {
    test('carrinho vazio: totais zerados', () {
      final summary = svc.summarize(items: []);
      expect(summary.grossTotal,         0.0);
      expect(summary.totalDiscountValue, 0.0);
      expect(summary.netTotal,           0.0);
      expect(summary.hasDiscounts,       isFalse);
    });

    test('carrier misto: gross/net calculados corretamente', () {
      final p1 = makeProduct(code: 'P1', price: 100.0);
      final p2 = makeProduct(code: 'P2', price: 200.0);

      final items = [
        makeCartItem(product: p1, quantity: 2, discount: 10.0), // 2×90 = 180
        makeCartItem(product: p2, quantity: 1, discount: 0.0),  // 1×200 = 200
      ];

      final summary = svc.summarize(items: items);

      // gross = 2×100 + 1×200 = 400
      expect(summary.grossTotal,         closeTo(400.0, 0.01));
      // totalDiscount = 2×10 + 0 = 20
      expect(summary.totalDiscountValue, closeTo(20.0, 0.01));
      // net = 400 - 20 = 380
      expect(summary.netTotal,           closeTo(380.0, 0.01));
      expect(summary.hasDiscounts,       isTrue);
    });

    test('itemsWithAlert: conta itens com desconto clampado', () {
      // Produto com limite 10%, pedido 30% → wasClamped = true → alert
      final p = makeProduct(price: 100.0, maxDiscount: 10.0);
      final items = [makeCartItem(product: p, quantity: 1, discount: 30.0)];

      final summary = svc.summarize(items: items);
      expect(summary.itemsWithAlert, 1);
    });
  });
}

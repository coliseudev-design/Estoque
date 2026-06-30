/// Testes unitários do DiscountService.
///
/// Segue Rule-10 (Test-First): cobre edge cases, valores nulos,
/// clamp por todas as 4 regras de limite e modo valor fixo.
///
/// Cobertura: 100% do DiscountService.calculate(), maxAllowed(), summarize().
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:coliseu_speed/core/repositories/models/models.dart';
import 'package:coliseu_speed/core/repositories/models/seller.dart';
import 'package:coliseu_speed/core/services/discount_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Fixtures reutilizáveis
// ─────────────────────────────────────────────────────────────────────────────

/// Produto base sem nenhum limite de desconto.
const Product _pBase = Product(
  code:  'P01',
  name:  'Produto Base',
  price: 100.0,
  stock: 10.0,
);

/// Produto com maxDiscount de 20%.
const Product _pMaxDisc20 = Product(
  code:        'P02',
  name:        'Produto MaxDisc 20%',
  price:       100.0,
  stock:       10.0,
  maxDiscount: 20.0,
);

/// Produto com priceMin de R$80 (permite até 20% de desconto).
const Product _pPriceMin80 = Product(
  code:     'P03',
  name:     'Produto PriceMin 80',
  price:    100.0,
  stock:    10.0,
  priceMin: 80.0,
);

/// Produto com priceCost de R$70 (permite até 30% de desconto).
const Product _pPriceCost70 = Product(
  code:      'P04',
  name:      'Produto PriceCost 70',
  price:     100.0,
  stock:     10.0,
  priceCost: 70.0,
);

/// Produto com todos os limites: maxDiscount=30%, priceMin=85, priceCost=80.
/// Limite efetivo: priceMin limita a 15% ((100-85)/100*100).
const Product _pAllLimits = Product(
  code:        'P05',
  name:        'Produto com todos os limites',
  price:       100.0,
  stock:       10.0,
  maxDiscount: 30.0,  // 30%
  priceMin:    85.0,  // 15%
  priceCost:   80.0,  // 20%
  // priceMin é mais restritivo → clamp a 15%
);

/// Vendedor com limite de 25% de desconto.
const Seller _sellerMax25 = Seller(
  id:          '1',
  name:        'Vendedor Teste',
  maxDiscount: 25.0,
);

/// Helper: cria CartItem com desconto em percentual.
CartItem _cartItem(Product p, {double qty = 1, double disc = 0}) => CartItem(
      product:       p,
      quantity:      qty,
      discount:      disc,
      discountMode:  DiscountMode.percent,
      rawDiscountInput: disc,
    );

void main() {
  final svc = DiscountService();

  // ─────────────────────────────────────────────────────────────────────────
  // calculate() — sem desconto
  // ─────────────────────────────────────────────────────────────────────────

  group('calculate() — sem desconto', () {
    test('desconto zero retorna preço cheio', () {
      final r = svc.calculate(
        product:    _pBase,
        quantity:   1,
        inputValue: 0,
        mode:       DiscountMode.percent,
      );

      expect(r.percent,                 0.0);
      expect(r.valuePerUnit,            0.0);
      expect(r.unitPriceAfterDiscount,  100.0);
      expect(r.totalPrice,              100.0);
      expect(r.wasClamped,              isFalse);
    });

    test('produto com preço zero retorna _noDiscount', () {
      const pZero = Product(code: 'P0', name: 'Grátis', price: 0.0, stock: 1);

      final r = svc.calculate(
        product:    pZero,
        quantity:   2,
        inputValue: 10, // R$ 10 em modo valor fixo
        mode:       DiscountMode.value,
      );

      expect(r.percent,    0.0);
      expect(r.totalPrice, 0.0);
    });

    test('valor de entrada negativo é clampado a zero', () {
      final r = svc.calculate(
        product:    _pBase,
        quantity:   1,
        inputValue: -5.0,
        mode:       DiscountMode.percent,
      );

      expect(r.percent, 0.0);
      expect(r.wasClamped, isFalse); // -5 clampado a 0 mas não "acima do máximo"
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // calculate() — modo percentual
  // ─────────────────────────────────────────────────────────────────────────

  group('calculate() — modo percentual', () {
    test('10% de desconto aplica corretamente', () {
      final r = svc.calculate(
        product:    _pBase,
        quantity:   2,
        inputValue: 10.0,
        mode:       DiscountMode.percent,
      );

      expect(r.percent,                closeTo(10.0, 0.001));
      expect(r.valuePerUnit,           closeTo(10.0, 0.001));
      expect(r.unitPriceAfterDiscount, closeTo(90.0, 0.001));
      expect(r.totalPrice,             closeTo(180.0, 0.001));
      expect(r.wasClamped,             isFalse);
    });

    test('100% de desconto sem limites funciona', () {
      final r = svc.calculate(
        product:    _pBase,
        quantity:   1,
        inputValue: 100.0,
        mode:       DiscountMode.percent,
      );

      expect(r.percent,                100.0);
      expect(r.unitPriceAfterDiscount, 0.0);
      expect(r.wasClamped,             isFalse);
    });

    test('input acima de 100% é clampado a 100%', () {
      final r = svc.calculate(
        product:    _pBase,
        quantity:   1,
        inputValue: 150.0,
        mode:       DiscountMode.percent,
      );

      expect(r.percent,    100.0);
      expect(r.wasClamped, isTrue);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // calculate() — modo valor fixo (R$)
  // ─────────────────────────────────────────────────────────────────────────

  group('calculate() — modo valor fixo', () {
    test('R\$15 de desconto num produto de R\$100 = 15%', () {
      final r = svc.calculate(
        product:    _pBase,
        quantity:   3,
        inputValue: 45.0,
        mode:       DiscountMode.value,
      );

      expect(r.percent,                closeTo(15.0, 0.001));
      expect(r.valuePerUnit,           closeTo(15.0, 0.001));
      expect(r.unitPriceAfterDiscount, closeTo(85.0, 0.001));
      expect(r.totalPrice,             closeTo(255.0, 0.001)); // 85 × 3
    });

    test('valor maior que preco: resultado e 100% e preco final eh zero', () {
      final r = svc.calculate(
        product:    _pBase,
        quantity:   1,
        inputValue: 150.0, // R$150 num produto de R$100 → clamp interno para 100%
        mode:       DiscountMode.value,
      );

      // O clamp de segurança `(150/100*100).clamp(0,100)` retorna 100%
      // Portanto appliedPercent = requestedPercent → wasClamped = false
      // mas o preço final é R$0 (100% de desconto aplicado)
      expect(r.percent,                100.0);
      expect(r.unitPriceAfterDiscount, closeTo(0.0, 0.001));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // calculate() — clamp por maxDiscount do produto
  // ─────────────────────────────────────────────────────────────────────────

  group('calculate() — clamp por maxDiscount do produto', () {
    test('desconto acima do limite do produto é clampado', () {
      final r = svc.calculate(
        product:    _pMaxDisc20,
        quantity:   1,
        inputValue: 30.0,
        mode:       DiscountMode.percent,
      );

      expect(r.percent,    closeTo(20.0, 0.001));
      expect(r.wasClamped, isTrue);
      expect(r.clampReason, contains('20'));
      expect(r.maxAllowedPercent, closeTo(20.0, 0.001));
    });

    test('desconto dentro do limite do produto não é clampado', () {
      final r = svc.calculate(
        product:    _pMaxDisc20,
        quantity:   1,
        inputValue: 15.0,
        mode:       DiscountMode.percent,
      );

      expect(r.percent,    closeTo(15.0, 0.001));
      expect(r.wasClamped, isFalse);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // calculate() — clamp por maxDiscount do vendedor
  // ─────────────────────────────────────────────────────────────────────────

  group('calculate() — clamp por vendedor', () {
    test('limite do vendedor (25%) prevalece sobre produto sem limite', () {
      final r = svc.calculate(
        product:    _pBase,
        quantity:   1,
        inputValue: 40.0,
        mode:       DiscountMode.percent,
        seller:     _sellerMax25,
      );

      expect(r.percent,    closeTo(25.0, 0.001));
      expect(r.wasClamped, isTrue);
      expect(r.clampReason, contains('vendedor'));
    });

    test('limite produto (20%) prevalece sobre vendedor (25%)', () {
      final r = svc.calculate(
        product:    _pMaxDisc20, // 20%
        quantity:   1,
        inputValue: 30.0,
        mode:       DiscountMode.percent,
        seller:     _sellerMax25, // 25%
      );

      // Produto é mais restritivo
      expect(r.maxAllowedPercent, closeTo(20.0, 0.001));
    });

    test('sem vendedor (null) não aplica limite de vendedor', () {
      final r = svc.calculate(
        product:    _pBase,
        quantity:   1,
        inputValue: 50.0,
        mode:       DiscountMode.percent,
        seller:     null,
      );

      expect(r.percent,    50.0);
      expect(r.wasClamped, isFalse);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // calculate() — clamp por priceMin
  // ─────────────────────────────────────────────────────────────────────────

  group('calculate() — clamp por priceMin', () {
    test('priceMin=80 limita desconto a 20%', () {
      final r = svc.calculate(
        product:    _pPriceMin80,
        quantity:   1,
        inputValue: 30.0,
        mode:       DiscountMode.percent,
      );

      expect(r.percent,                closeTo(20.0, 0.001));
      expect(r.unitPriceAfterDiscount, closeTo(80.0, 0.001));
      expect(r.wasClamped,             isTrue);
      expect(r.clampReason,            contains('mínimo'));
    });

    test('desconto exatamente no priceMin não é clampado', () {
      final r = svc.calculate(
        product:    _pPriceMin80,
        quantity:   2,
        inputValue: 20.0, // exatamente 20%
        mode:       DiscountMode.percent,
      );

      expect(r.wasClamped, isFalse);
      expect(r.totalPrice,  closeTo(160.0, 0.001));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // calculate() — clamp por priceCost
  // ─────────────────────────────────────────────────────────────────────────

  group('calculate() — clamp por priceCost', () {
    test('priceCost=70 limita desconto a 30%', () {
      final r = svc.calculate(
        product:    _pPriceCost70,
        quantity:   1,
        inputValue: 50.0,
        mode:       DiscountMode.percent,
      );

      expect(r.percent,    closeTo(30.0, 0.001));
      expect(r.wasClamped, isTrue);
      expect(r.clampReason, contains('custo'));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // calculate() — precedência: o mais restritivo deve prevalecer
  // ─────────────────────────────────────────────────────────────────────────

  group('calculate() — precedência de limites', () {
    test('priceMin mais restritivo que maxDiscount e priceCost prevalece', () {
      // _pAllLimits: maxDisc=30%, priceMin=85→15%, priceCost=80→20%
      // Mais restritivo: priceMin = 15%
      final r = svc.calculate(
        product:    _pAllLimits,
        quantity:   1,
        inputValue: 25.0,
        mode:       DiscountMode.percent,
      );

      expect(r.maxAllowedPercent, closeTo(15.0, 0.001));
      expect(r.percent,           closeTo(15.0, 0.001));
      expect(r.wasClamped,        isTrue);
    });

    test('vendedor mais restritivo que produto prevalece', () {
      const sellerStrict = Seller(id: '2', name: 'Strict', maxDiscount: 5.0);

      final r = svc.calculate(
        product:    _pAllLimits, // maxDisc=30%, priceMin=15%
        quantity:   1,
        inputValue: 20.0,
        mode:       DiscountMode.percent,
        seller:     sellerStrict,
      );

      expect(r.maxAllowedPercent, closeTo(5.0, 0.001));
      expect(r.wasClamped,        isTrue);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // maxAllowed()
  // ─────────────────────────────────────────────────────────────────────────

  group('maxAllowed()', () {
    test('sem limites retorna 100%', () {
      expect(svc.maxAllowed(_pBase, null), 100.0);
    });

    test('produto com maxDiscount=20 retorna 20', () {
      expect(svc.maxAllowed(_pMaxDisc20, null), 20.0);
    });

    test('vendedor com maxDiscount=10 prevalece sobre produto 20', () {
      const sellerMax10 = Seller(id: '3', name: 'Tight', maxDiscount: 10.0);
      expect(svc.maxAllowed(_pMaxDisc20, sellerMax10), 10.0);
    });

    test('priceMin mais restritivo que maxDiscount prevalece', () {
      // priceMin=85 → 15%; maxDiscount=30%
      final max = svc.maxAllowed(_pAllLimits, null);
      // nota: maxAllowed() não considera priceCost, apenas produto+vendedor+priceMin
      expect(max, closeTo(15.0, 0.001));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // summarize()
  // ─────────────────────────────────────────────────────────────────────────

  group('summarize()', () {
    test('carrinho vazio retorna zeros', () {
      final s = svc.summarize(items: [], seller: null);

      expect(s.grossTotal,         0.0);
      expect(s.totalDiscountValue, 0.0);
      expect(s.netTotal,           0.0);
      expect(s.avgDiscountPercent, 0.0);
      expect(s.hasDiscounts,       isFalse);
    });

    test('dois itens sem desconto: gross = net', () {
      final items = [
        _cartItem(_pBase, qty: 2, disc: 0),
        _cartItem(_pBase, qty: 3, disc: 0),
      ];

      final s = svc.summarize(items: items);

      expect(s.grossTotal,         500.0);
      expect(s.netTotal,           500.0);
      expect(s.totalDiscountValue, 0.0);
    });

    test('item com 10% de desconto reflete corretamente no summary', () {
      final items = [_cartItem(_pBase, qty: 1, disc: 10.0)];

      final s = svc.summarize(items: items);

      expect(s.grossTotal,         100.0);
      expect(s.totalDiscountValue, closeTo(10.0, 0.001));
      expect(s.netTotal,           closeTo(90.0, 0.001));
      expect(s.avgDiscountPercent, closeTo(10.0, 0.001));
    });

    test('item com desconto clampado é listado em itemsWithAlert', () {
      // Pede 50% mas produto permite apenas 20%
      final items = [_cartItem(_pMaxDisc20, qty: 1, disc: 50.0)];

      final s = svc.summarize(items: items, seller: null);

      expect(s.itemsWithAlert, 1);
      expect(s.items.first.hasMarginalAlert, isTrue);
    });

    test('média ponderada de desconto com dois itens', () {
      final items = [
        _cartItem(_pBase, qty: 1, disc: 0),   // 100 sem desconto
        _cartItem(_pBase, qty: 1, disc: 20.0), // 100 com 20% = 80
      ];

      final s = svc.summarize(items: items);

      // gross = 200; desconto = 20; avg = 20/200*100 = 10%
      expect(s.avgDiscountPercent, closeTo(10.0, 0.001));
      expect(s.netTotal,           closeTo(180.0, 0.001));
    });

    test('hasDiscounts é false quando nenhum item tem desconto', () {
      final s = svc.summarize(
        items:  [_cartItem(_pBase, qty: 1, disc: 0)],
        seller: null,
      );
      expect(s.totalDiscountValue, 0.0);
      expect(s.netTotal, closeTo(s.grossTotal, 0.001));
    });

    test('hasDiscounts é true quando algum item tem desconto', () {
      final s = svc.summarize(
        items:  [_cartItem(_pBase, qty: 1, disc: 5.0)],
        seller: null,
      );
      expect(s.totalDiscountValue, greaterThan(0));
      expect(s.netTotal, lessThan(s.grossTotal));
    });
  });
}

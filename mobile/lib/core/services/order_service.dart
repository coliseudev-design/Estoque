/// OrderService — Lógica de negócios para criação e validação de pedidos.
///
/// Centraliza regras de desconto, cálculo de totais e validações
/// que antes estavam espalhadas nas telas (NewOrderScreen, ProductPicker).
///
/// Regra: Router/UI valida input; Service aplica regras de negócio.
library;

import 'package:flutter/foundation.dart';
import '../database/database_helper.dart';

/// Resultado da validação de um pedido antes do envio.
class OrderValidation {
  final bool isValid;
  final List<String> errors;

  const OrderValidation({this.isValid = true, this.errors = const []});
  const OrderValidation.invalid(this.errors) : isValid = false;
}

/// Item de pedido com cálculos aplicados.
class OrderItemCalc {
  final String productCode;
  final String productName;
  final double quantity;
  final double unitPrice;
  final double discountPercent;
  final double discountValue;
  final double totalPrice;

  const OrderItemCalc({
    required this.productCode,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.discountPercent,
    required this.discountValue,
    required this.totalPrice,
  });
}

class OrderService {
  final DatabaseHelper _db;

  OrderService(this._db);

  /// Calcula o preço total de um item aplicando desconto.
  ///
  /// Suporta dois modos:
  /// - 'percent': desconto em % sobre o unitário
  /// - 'value': desconto em R$ absoluto por unidade
  ///
  /// Args:
  ///   unitPrice: Preço unitário do produto (deve ser >= 0)
  ///   quantity: Quantidade (deve ser >= 1)
  ///   discount: Valor do desconto (% ou R$)
  ///   mode: 'percent' ou 'value'
  ///
  /// Returns:
  ///   OrderItemCalc com valores calculados
  ///
  /// Raises:
  ///   ArgumentError se unitPrice < 0 ou quantity < 1
  OrderItemCalc calculateItem({
    required String productCode,
    required String productName,
    required double unitPrice,
    required double quantity,
    required double discount,
    required String mode,
  }) {
    if (unitPrice < 0) throw ArgumentError('Preço não pode ser negativo');
    if (quantity < 1) throw ArgumentError('Quantidade deve ser pelo menos 1');

    double discountPercent;
    double discountValue;
    double effectiveUnitPrice;

    if (mode == 'percent') {
      discountPercent = discount.clamp(0.0, 100.0);
      discountValue = unitPrice * (discountPercent / 100);
      effectiveUnitPrice = unitPrice - discountValue;
    } else {
      discountValue = discount.clamp(0.0, unitPrice);
      discountPercent = unitPrice > 0 ? (discountValue / unitPrice * 100) : 0;
      effectiveUnitPrice = unitPrice - discountValue;
    }

    final totalPrice = effectiveUnitPrice * quantity;

    return OrderItemCalc(
      productCode: productCode,
      productName: productName,
      quantity: quantity,
      unitPrice: unitPrice,
      discountPercent: discountPercent,
      discountValue: discountValue,
      totalPrice: totalPrice > 0 ? totalPrice : 0,
    );
  }

  /// Valida o desconto contra o limite máximo do produto.
  ///
  /// Args:
  ///   discountPercent: Desconto aplicado (%)
  ///   maxDiscount: Desconto máximo permitido (%)
  ///   sellerMaxDiscount: Desconto máximo do vendedor (%)
  ///
  /// Returns:
  ///   true se o desconto está dentro dos limites
  bool isDiscountAllowed({
    required double discountPercent,
    double? maxDiscount,
    double? sellerMaxDiscount,
  }) {
    final limit = _effectiveMaxDiscount(maxDiscount, sellerMaxDiscount);
    return discountPercent <= limit;
  }

  /// Calcula o desconto máximo efetivo (menor entre produto e vendedor).
  double _effectiveMaxDiscount(double? productMax, double? sellerMax) {
    if (productMax == null && sellerMax == null) return 100.0;
    if (productMax == null) return sellerMax!;
    if (sellerMax == null) return productMax;
    return productMax < sellerMax ? productMax : sellerMax;
  }

  /// Valida um pedido completo antes de salvar/sincronizar.
  OrderValidation validate({
    required String? customerId,
    required String? paymentSpeciesId,
    required List<OrderItemCalc> items,
  }) {
    final errors = <String>[];

    if (customerId == null || customerId.isEmpty) {
      errors.add('Selecione um cliente');
    }
    if (paymentSpeciesId == null || paymentSpeciesId.isEmpty) {
      errors.add('Selecione uma forma de pagamento');
    }
    if (items.isEmpty) {
      errors.add('Adicione pelo menos um produto');
    }

    final invalidItems = items.where((i) => i.totalPrice <= 0).toList();
    if (invalidItems.isNotEmpty) {
      errors.add('${invalidItems.length} item(ns) com valor zero');
    }

    if (errors.isEmpty) return const OrderValidation();
    return OrderValidation.invalid(errors);
  }

  /// Retorna estatísticas de vendas por período.
  ///
  /// Args:
  ///   days: Número de dias para trás a partir de hoje
  ///
  /// Returns:
  ///   Lista de {date, total, count} por dia
  Future<List<Map<String, dynamic>>> salesByDay({int days = 7}) async {
    final db = await _db.database;
    final since = DateTime.now().subtract(Duration(days: days)).toIso8601String();

    return db.rawQuery('''
      SELECT
        DATE(created_at) AS date,
        SUM(total_amount) AS total,
        COUNT(*) AS count
      FROM orders
      WHERE created_at >= ?
      GROUP BY DATE(created_at)
      ORDER BY date DESC
    ''', [since]);
  }

  /// Retorna o ranking dos produtos mais vendidos.
  Future<List<Map<String, dynamic>>> topProducts({int limit = 10}) async {
    final db = await _db.database;

    return db.rawQuery('''
      SELECT
        oi.product_code,
        oi.product_name,
        SUM(oi.quantity) AS total_qty,
        SUM(oi.total_price) AS total_revenue,
        COUNT(DISTINCT o.id) AS order_count
      FROM order_items oi
      INNER JOIN orders o ON o.id = oi.order_id
      GROUP BY oi.product_code
      ORDER BY total_qty DESC
      LIMIT ?
    ''', [limit]);
  }

  /// Retorna o ranking dos clientes por faturamento.
  Future<List<Map<String, dynamic>>> topCustomers({int limit = 5}) async {
    final db = await _db.database;

    return db.rawQuery('''
      SELECT
        customer_id,
        customer_name,
        SUM(total_amount) AS total_revenue,
        COUNT(*) AS order_count,
        AVG(total_amount) AS avg_ticket
      FROM orders
      GROUP BY customer_id
      ORDER BY total_revenue DESC
      LIMIT ?
    ''', [limit]);
  }
}

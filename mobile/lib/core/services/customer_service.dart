/// CustomerService — Dados comerciais e analytics de clientes.
///
/// Fornece visão 360° do cliente para o vendedor em campo:
/// último pedido, ticket médio, total comprado, dias sem comprar,
/// histórico de pedidos, títulos financeiros.
///
/// Todos os dados são 100% locais (SQLite).
library;

import '../database/database_helper.dart';

/// Resumo comercial de um cliente.
class CustomerInsight {
  final String customerId;
  final String customerName;
  final DateTime? lastOrderDate;
  final int daysSinceLastOrder;
  final double totalPurchased;
  final double averageTicket;
  final int totalOrders;
  final double openBalance;

  const CustomerInsight({
    required this.customerId,
    required this.customerName,
    this.lastOrderDate,
    this.daysSinceLastOrder = 0,
    this.totalPurchased = 0.0,
    this.averageTicket = 0.0,
    this.totalOrders = 0,
    this.openBalance = 0.0,
  });
}

class CustomerService {
  final DatabaseHelper _db;

  CustomerService(this._db);

  /// Retorna a visão comercial completa de um cliente.
  ///
  /// Usa dados locais de pedidos + financials.
  Future<CustomerInsight> getInsight(String customerId) async {
    final db = await _db.database;

    // Estatísticas de pedidos
    final orderRows = await db.rawQuery('''
      SELECT
        COUNT(*)                       AS total_orders,
        COALESCE(SUM(total_amount), 0) AS total_purchased,
        COALESCE(AVG(total_amount), 0) AS avg_ticket,
        MAX(created_at)                AS last_order_date
      FROM orders
      WHERE customer_id = ?
    ''', [customerId]);

    // Saldo em aberto (títulos não pagos)
    final finRows = await db.rawQuery('''
      SELECT COALESCE(SUM(amount), 0) AS open_balance
      FROM financials
      WHERE customer_id = ? AND is_paid = 0
    ''', [customerId]);

    // Nome do cliente
    final custRows = await db.query('customers', where: 'id = ?', whereArgs: [customerId], limit: 1);
    final customerName = custRows.isNotEmpty ? (custRows.first['name'] as String? ?? '') : '';

    final orderRow = orderRows.first;
    final totalOrders = (orderRow['total_orders'] as num?)?.toInt() ?? 0;
    final totalPurchased = (orderRow['total_purchased'] as num?)?.toDouble() ?? 0.0;
    final avgTicket = (orderRow['avg_ticket'] as num?)?.toDouble() ?? 0.0;
    final lastOrderStr = orderRow['last_order_date'] as String?;
    final lastOrderDate = lastOrderStr != null ? DateTime.tryParse(lastOrderStr) : null;

    final openBalance = (finRows.first['open_balance'] as num?)?.toDouble() ?? 0.0;

    final daysSince = lastOrderDate != null
        ? DateTime.now().difference(lastOrderDate).inDays
        : 0;

    return CustomerInsight(
      customerId: customerId,
      customerName: customerName,
      lastOrderDate: lastOrderDate,
      daysSinceLastOrder: daysSince,
      totalPurchased: totalPurchased,
      averageTicket: avgTicket,
      totalOrders: totalOrders,
      openBalance: openBalance,
    );
  }

  /// Retorna os últimos [limit] pedidos de um cliente.
  Future<List<Map<String, dynamic>>> orderHistory(
    String customerId, {
    int limit = 20,
  }) async {
    final db = await _db.database;
    return db.query(
      'orders',
      where: 'customer_id = ?',
      whereArgs: [customerId],
      orderBy: 'created_at DESC',
      limit: limit,
    );
  }

  /// Retorna os produtos mais comprados por um cliente (para sugestão).
  ///
  /// Agrupa por product_code e soma quantidades.
  Future<List<Map<String, dynamic>>> topProducts(
    String customerId, {
    int limit = 10,
  }) async {
    final db = await _db.database;
    return db.rawQuery('''
      SELECT
        oi.product_code,
        oi.product_name,
        SUM(oi.quantity) AS total_qty,
        COUNT(*)         AS times_ordered
      FROM order_items oi
      INNER JOIN orders o ON o.id = oi.order_id
      WHERE o.customer_id = ?
      GROUP BY oi.product_code
      ORDER BY total_qty DESC
      LIMIT ?
    ''', [customerId, limit]);
  }
}

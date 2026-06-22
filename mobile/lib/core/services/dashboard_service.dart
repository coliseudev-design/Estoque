/// DashboardService — Agrega KPIs comerciais do vendedor a partir do SQLite.
///
/// Todos os dados são 100% locais (offline-first).
/// Sem acesso direto ao Firebird — apenas SQLite.
///
/// KPIs: pedidos hoje, valor vendido, ticket médio, clientes atendidos,
/// pendentes de sync, meta diária.
library;

import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';

/// Snapshot dos KPIs do vendedor para o dashboard.
class DashboardKpis {
  final int ordersToday;
  final double totalSoldToday;
  final double totalSoldMonth;
  final double averageTicket;
  final int customersServedToday;
  final int pendingSync;
  final int errorSync;
  final int totalProducts;
  final int totalCustomers;
  final String lastSyncDate;

  const DashboardKpis({
    this.ordersToday = 0,
    this.totalSoldToday = 0.0,
    this.totalSoldMonth = 0.0,
    this.averageTicket = 0.0,
    this.customersServedToday = 0,
    this.pendingSync = 0,
    this.errorSync = 0,
    this.totalProducts = 0,
    this.totalCustomers = 0,
    this.lastSyncDate = '',
  });
}

class DashboardService {
  final DatabaseHelper _db;

  DashboardService(this._db);

  /// Carrega todos os KPIs do vendedor em uma única chamada.
  ///
  /// Usa queries agregadas otimizadas (índices: idx_orders_sync_date,
  /// idx_orders_customer, idx_orders_created).
  Future<DashboardKpis> loadKpis({required String companyId}) async {
    final db = await _db.database;
    final today = _todayIso();
    final now = DateTime.now();
    final monthPrefix = '${now.year}-${now.month.toString().padLeft(2, '0')}';

    // Executa todas as queries em paralelo
    final results = await Future.wait([
      _orderStatsToday(db, today, companyId),
      _syncCounts(db, companyId),
      _catalogCounts(db),
      _db.getSyncMetadata('last_catalog_sync'),
      _orderStatsMonth(db, monthPrefix, companyId),
    ]);

    final orderStats = results[0] as Map<String, dynamic>;
    final syncCounts = results[1] as Map<String, int>;
    final catalogCounts = results[2] as Map<String, int>;
    final lastSyncDate = (results[3] as String?) ?? '';
    final totalSoldMonth = results[4] as double;

    return DashboardKpis(
      ordersToday: orderStats['count'] as int,
      totalSoldToday: orderStats['total'] as double,
      totalSoldMonth: totalSoldMonth,
      averageTicket: orderStats['avg'] as double,
      customersServedToday: orderStats['customers'] as int,
      pendingSync: syncCounts['pending'] ?? 0,
      errorSync: syncCounts['error'] ?? 0,
      totalProducts: catalogCounts['products'] ?? 0,
      totalCustomers: catalogCounts['customers'] ?? 0,
      lastSyncDate: lastSyncDate,
    );
  }

  /// Lista os últimos [limit] pedidos do vendedor.
  Future<List<Map<String, dynamic>>> recentOrders({required String companyId, int limit = 5}) async {
    final db = await _db.database;
    return db.query(
      'orders',
      where: 'company_id = ?',
      whereArgs: [companyId],
      orderBy: 'created_at DESC',
      limit: limit,
    );
  }

  // ── Queries internas ──────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _orderStatsToday(Database db, String today, String companyId) async {
    final rows = await db.rawQuery('''
      SELECT 
        COUNT(*)                      AS cnt,
        COALESCE(SUM(total_amount), 0) AS total,
        COALESCE(AVG(total_amount), 0) AS avg_ticket,
        COUNT(DISTINCT customer_id)    AS customers
      FROM orders
      WHERE created_at >= ? AND company_id = ? AND sync_status != 'draft'
    ''', [today, companyId]);

    final row = rows.first;
    return {
      'count': (row['cnt'] as num?)?.toInt() ?? 0,
      'total': (row['total'] as num?)?.toDouble() ?? 0.0,
      'avg': (row['avg_ticket'] as num?)?.toDouble() ?? 0.0,
      'customers': (row['customers'] as num?)?.toInt() ?? 0,
    };
  }

  Future<Map<String, int>> _syncCounts(Database db, String companyId) async {
    final rows = await db.rawQuery('''
      SELECT 
        sync_status,
        COUNT(*) AS cnt
      FROM orders
      WHERE sync_status IN ('pending', 'error') AND company_id = ?
      GROUP BY sync_status
    ''', [companyId]);

    final map = <String, int>{};
    for (final row in rows) {
      map[row['sync_status'] as String] = (row['cnt'] as num).toInt();
    }
    return map;
  }

  Future<Map<String, int>> _catalogCounts(Database db) async {
    final rows = await db.rawQuery('''
      SELECT
        (SELECT COUNT(*) FROM products)  AS products,
        (SELECT COUNT(*) FROM customers) AS customers
    ''');
    final row = rows.first;
    return {
      'products': (row['products'] as num?)?.toInt() ?? 0,
      'customers': (row['customers'] as num?)?.toInt() ?? 0,
    };
  }

  Future<double> _orderStatsMonth(Database db, String monthPrefix, String companyId) async {
    final rows = await db.rawQuery('''
      SELECT COALESCE(SUM(total_amount), 0) AS total
      FROM orders
      WHERE created_at LIKE ? AND company_id = ? AND sync_status != 'draft'
    ''', ['$monthPrefix%', companyId]);
    if (rows.isEmpty) return 0.0;
    return (rows.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  String _todayIso() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day).toIso8601String();
  }
}

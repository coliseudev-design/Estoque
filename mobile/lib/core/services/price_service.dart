/// PriceService — resolução de preço por tabela de preço do cliente.
///
/// Regra de resolução:
///   Se customer.priceTableId != null:
///     → Busca ProductPrice(productCode, priceTableId) no SQLite
///     → Se encontrado: usa esse preço
///     → Se não encontrado: usa produto.price padrão
///   Senão:
///     → Usa produto.price padrão
///
/// Rule-06: lógica de negócio isolada em Services/.
library;

import 'package:flutter/foundation.dart';
import '../database/database_helper.dart';
import '../repositories/models/models.dart';


class PriceService {
  final DatabaseHelper _db;

  PriceService({DatabaseHelper? db}) : _db = db ?? DatabaseHelper();

  /// Retorna o preço correto do produto para este cliente.
  ///
  /// [basePrice] é o preço padrão (PRODUTO_PRECOS.PRECO_TABELA).
  /// [productCode] é o código do produto (PRODUTOS.ID_PRODUTO).
  /// [priceTableId] é a tabela vinculada ao cliente (CLIENTES.ID_TABELA).
  ///   Se null → retorna o preço base.
  ///
  /// Retorna:
  ///   - Preço da tabela se o produto tiver entrada em product_prices
  ///   - Preço base (basePrice) caso contrário
  Future<double> resolvePrice({
    required double basePrice,
    required String productCode,
    String? priceTableId,
  }) async {
    if (priceTableId == null || priceTableId.isEmpty) return basePrice;

    try {
      final db = await _db.database;
      final rows = await db.query(
        'product_prices',
        columns: ['price'],
        where: 'product_code = ? AND price_table_id = ?',
        whereArgs: [productCode, priceTableId],
        limit: 1,
      );

      if (rows.isNotEmpty) {
        final tablePrice = (rows.first['price'] as num).toDouble();
        // Garante que o preço da tabela é positivo
        return tablePrice > 0 ? tablePrice : basePrice;
      }
    } catch (_) {
      // Em caso de erro de banco, retorna preço base sem derrubar o pedido
    }

    return basePrice;
  }

  /// Retorna os preços de uma lista de produtos, aplicando a tabela de preço
  /// especificada. Para produtos que não estão na tabela, mantém o preço base.
  Future<Map<String, double>> resolvePrices({
    required List<Product> products,
    String? priceTableId,
  }) async {
    final map = <String, double>{};
    for (final p in products) {
      map[p.code] = p.price;
    }

    if (priceTableId == null || priceTableId.isEmpty || products.isEmpty) {
      return map;
    }

    try {
      final db = await _db.database;
      final codes = products.map((p) => p.code).toList();
      final placeholders = List.filled(codes.length, '?').join(',');

      final rows = await db.query(
        'product_prices',
        columns: ['product_code', 'price'],
        where: 'price_table_id = ? AND product_code IN ($placeholders)',
        whereArgs: [priceTableId, ...codes],
      );

      for (final row in rows) {
        final code = row['product_code'] as String;
        final tablePrice = (row['price'] as num).toDouble();
        if (tablePrice > 0) {
          map[code] = tablePrice;
        }
      }
    } catch (e) {
      // Fallback seguro: mantém preço base — produto não vai ao pedido com R$0
      debugPrint('[PriceService] Erro ao buscar preços da tabela $priceTableId: $e');
    }

    return map;
  }

  /// Retorna o nome da tabela de preço ativa para um cliente.
  /// Retorna null se o cliente não tiver tabela vinculada.
  Future<String?> getActiveTableName(String? priceTableId) async {
    if (priceTableId == null || priceTableId.isEmpty) return null;

    try {
      final db = await _db.database;
      final rows = await db.query(
        'price_tables',
        columns: ['name'],
        where: 'id = ?',
        whereArgs: [priceTableId],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        return rows.first['name'] as String?;
      }
    } catch (e) {
      debugPrint('[PriceService] Erro ao buscar nome da tabela $priceTableId: $e');
    }

    return null;
  }
}

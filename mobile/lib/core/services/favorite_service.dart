/// FavoriteService — Gerenciamento de produtos favoritos.
///
/// CRUD local (SQLite). Favoritos são por dispositivo/instalação.
/// Tabela: product_favorites (code TEXT PK, added_at TEXT).
library;

import '../database/database_helper.dart';

/// Serviço de favoritos de produtos.
///
/// Todos os dados são 100% locais — não sincroniza com ERP.
class FavoriteService {
  final DatabaseHelper _db;

  FavoriteService(this._db);

  /// Verifica se um produto está marcado como favorito.
  Future<bool> isFavorite(String code) async {
    final db = await _db.database;
    final rows = await db.query(
      'product_favorites',
      where: 'code = ?',
      whereArgs: [code],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Alterna o status de favorito de um produto.
  ///
  /// Retorna `true` se o produto foi adicionado, `false` se removido.
  Future<bool> toggle(String code) async {
    final db = await _db.database;
    final exists = await isFavorite(code);
    if (exists) {
      await db.delete('product_favorites', where: 'code = ?', whereArgs: [code]);
      return false;
    } else {
      await db.insert('product_favorites', {
        'code': code,
        'added_at': DateTime.now().toIso8601String(),
      });
      return true;
    }
  }

  /// Retorna os códigos de todos os produtos favoritos.
  Future<Set<String>> allCodes() async {
    final db = await _db.database;
    final rows = await db.query('product_favorites', columns: ['code']);
    return rows.map((r) => r['code'] as String).toSet();
  }

  /// Retorna a contagem de favoritos.
  Future<int> count() async {
    final db = await _db.database;
    final r = await db.rawQuery('SELECT COUNT(*) AS c FROM product_favorites');
    return (r.first['c'] as num?)?.toInt() ?? 0;
  }
}

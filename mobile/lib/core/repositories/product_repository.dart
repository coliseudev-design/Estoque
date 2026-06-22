/// ProductRepository — Acesso a dados de produtos no SQLite local.
///
/// Regra (Clean Architecture): Esta camada só fala com o DatabaseHelper.
/// Nenhuma lógica de negócio aqui — apenas queries e mapeamento de dados.
library;

import '../database/database_helper.dart';
import 'models/product.dart';

/// Campo de busca para filtrar produtos.
///
/// Quando [searchField] é null no método [ProductRepository.search],
/// a busca é feita em todos os campos (nome + código + referência + barcode + marca).
enum SearchField {
  /// Busca pelo nome/descrição do produto.
  description,

  /// Busca pelo código do produto (chave primária).
  code,

  /// Busca pela referência do produto.
  reference,

  /// Busca pelo código de barras (EAN).
  barCode,

  /// Busca pela marca/laboratório.
  brand;

  /// Label amigável para exibição no dropdown.
  String get label => switch (this) {
    SearchField.description => 'Descrição',
    SearchField.code        => 'Código',
    SearchField.reference   => 'Referência',
    SearchField.barCode     => 'Cód. Barras',
    SearchField.brand       => 'Marca',
  };

  /// Coluna correspondente no SQLite.
  String get _column => switch (this) {
    SearchField.description => 'name',
    SearchField.code        => 'code',
    SearchField.reference   => 'reference',
    SearchField.barCode     => 'bar_code',
    SearchField.brand       => 'brand',
  };
}

class ProductRepository {
  final DatabaseHelper _db;

  ProductRepository({required DatabaseHelper db}) : _db = db;

  // ─────────────────────────────────────────────────────────────────────────
  // Busca e listagem
  // ─────────────────────────────────────────────────────────────────────────

  /// Busca produtos com debounce aplicado pelo chamador.
  ///
  /// @param query        Texto de busca. Vazio = retorna tudo.
  /// @param searchField  Campo específico para buscar. Null = busca em todos os campos.
  /// @param brand        Filtra por marca (LABORATORIOS.NOME). Null = todas.
  /// @param limit        Máximo de resultados (padrão 1200).
  Future<List<Product>> search(
    String query, {
    SearchField? searchField,
    String? brand,
    int limit = 1200,
  }) async {
    final db   = await _db.database;
    final term = '%${query.trim().toLowerCase()}%';

    final where     = <String>[];
    final whereArgs = <dynamic>[];

    if (query.trim().isNotEmpty) {
      if (searchField != null) {
        // Busca em campo específico
        where.add('LOWER(${searchField._column}) LIKE ?');
        whereArgs.add(term);
      } else {
        // Busca em todos os campos relevantes
        where.add(
          '(LOWER(name) LIKE ? OR LOWER(code) LIKE ? OR LOWER(reference) LIKE ? OR LOWER(bar_code) LIKE ? OR LOWER(brand) LIKE ?)',
        );
        whereArgs.addAll([term, term, term, term, term]);
      }
    }
    if (brand != null) {
      where.add('brand = ?');
      whereArgs.add(brand);
    }

    final rows = await db.query(
      'products',
      where:     where.isEmpty ? null : where.join(' AND '),
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy:   'name ASC',
      limit:     limit,
    );
    return rows.map(Product.fromMap).toList();
  }

  /// Retorna marcas distintas (LABORATORIOS.NOME) presentes no catálogo.
  Future<List<String>> getBrands() async {
    final db   = await _db.database;
    final rows = await db.rawQuery(
      "SELECT DISTINCT brand FROM products WHERE brand IS NOT NULL AND TRIM(brand) != '' ORDER BY brand ASC",
    );
    return rows.map((r) => r['brand'] as String).toList();
  }

  /// Retorna um produto específico pelo código.
  /// Retorna null se não encontrado.
  ///
  /// @param code  Código do produto (chave primária no SQLite).
  Future<Product?> getByCode(String code) async {
    final database = await _db.database;
    final rows = await database.query(
      'products',
      where: 'code = ?',
      whereArgs: [code],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Product.fromMap(rows.first);
  }

  /// Busca um produto pelo código de barras (EAN) exato.
  ///
  /// Usado pelo scanner PDV para localizar o produto rapidamente.
  /// Retorna null se nenhum produto tiver esse barcode.
  Future<Product?> findByBarcode(String barcode) async {
    final database = await _db.database;
    final rows = await database.query(
      'products',
      where: 'bar_code = ?',
      whereArgs: [barcode.trim()],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Product.fromMap(rows.first);
  }

  /// Conta o total de produtos no cache local.
  /// Usado para indicar ao usuário quantos itens existem antes de buscar.
  Future<int> count() async {
    final database = await _db.database;
    final result = await database.rawQuery('SELECT COUNT(*) as total FROM products');
    return result.first['total'] as int;
  }
}

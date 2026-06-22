/// CustomerRepository — Acesso a dados de clientes no SQLite local.
///
/// REGRA (Rule-06 Clean Architecture): apenas queries e mapeamento.
/// Nenhuma lógica de negócio. O SyncService cuida do pull do Firebird.
library;

import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import 'models/customer.dart';

class CustomerRepository {
  final DatabaseHelper _db;

  CustomerRepository({required DatabaseHelper db}) : _db = db;

  // ─────────────────────────────────────────────────────────────────────────
  // Busca
  // ─────────────────────────────────────────────────────────────────────────

  /// Busca clientes por nome ou CNPJ com debounce aplicado pelo chamador.
  ///
  /// Query vazia retorna os primeiros [limit] clientes (ordem alfabética).
  ///
  /// @param query  Texto de busca (nome ou CNPJ). Vazio = retorna tudo.
  /// @param limit  Máximo de resultados (padrão 100 para listas virtualizadas).
  /// @returns      Lista de [Customer] mapeados do SQLite.
  Future<List<Customer>> search(String query, {int limit = 100}) async {
    final db   = await _db.database;
    final term = '%${query.trim().toLowerCase()}%';

    final rows = query.trim().isEmpty
        ? await db.query(
            'customers',
            orderBy: 'name ASC',
            limit: limit,
          )
        : await db.query(
            'customers',
            where: 'LOWER(name) LIKE ? OR cnpj LIKE ?',
            whereArgs: [term, term],
            orderBy: 'name ASC',
            limit: limit,
          );

    return rows.map(Customer.fromMap).toList();
  }

  /// Retorna um cliente específico pelo ID.
  /// Retorna null se não encontrado.
  Future<Customer?> getById(String id) async {
    final db   = await _db.database;
    final rows = await db.query(
      'customers',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Customer.fromMap(rows.first);
  }

  /// Busca um cliente local pelo CNPJ ou CPF (com ou sem formatação).
  Future<Customer?> getByCnpjOrCpf(String document) async {
    final db     = await _db.database;
    final digits = document.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return null;

    String formatted;
    if (digits.length == 11) {
      formatted = '${digits.substring(0, 3)}.${digits.substring(3, 6)}.${digits.substring(6, 9)}-${digits.substring(9)}';
    } else if (digits.length == 14) {
      formatted = '${digits.substring(0, 2)}.${digits.substring(2, 5)}.${digits.substring(5, 8)}/${digits.substring(8, 12)}-${digits.substring(12)}';
    } else {
      formatted = digits;
    }

    final rows = await db.query(
      'customers',
      where: 'cnpj = ? OR cnpj = ?',
      whereArgs: [digits, formatted],
      limit: 1,
    );

    return rows.isEmpty ? null : Customer.fromMap(rows.first);
  }

  /// Conta o total de clientes no cache local.
  Future<int> count() async {
    final db     = await _db.database;
    final result = await db.rawQuery('SELECT COUNT(*) as total FROM customers');
    return result.first['total'] as int;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Upsert batch (usado pelo SyncService.pullCustomers e _NewCustomerSheet)
  // ─────────────────────────────────────────────────────────────────────────

  /// Insere ou atualiza clientes em batch.
  Future<void> upsertBatch(List<Customer> customers) async {
    if (customers.isEmpty) return;
    final db    = await _db.database;
    final batch = db.batch();
    final now   = DateTime.now().toIso8601String();
    for (final c in customers) {
      batch.insert(
        'customers',
        {...c.toMap(), 'last_synced_at': now},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// Retorna clientes criados localmente (ainda não enviados ao ERP).
  /// IDs locais têm prefixo "local_".
  Future<List<Customer>> getLocalCustomers() async {
    final db = await _db.database;
    final rows = await db.query(
      'customers',
      where: "id LIKE 'local_%'",
      orderBy: 'name ASC',
    );
    return rows.map(Customer.fromMap).toList();
  }

  /// Atualiza o ID do cliente de [localId] para [erpId] após push bem-sucedido.
  ///
  /// Também atualiza referências em pedidos locais que usavam o localId.
  Future<void> updateErpId(String localId, String erpId) async {
    final db = await _db.database;
    await db.update(
      'customers',
      {'id': erpId},
      where: 'id = ?',
      whereArgs: [localId],
    );
    // Atualiza pedidos locais que referenciam o cliente com ID local
    await db.update(
      'orders',
      {'customer_id': erpId},
      where: "customer_id = ?",
      whereArgs: [localId],
    );
  }
}

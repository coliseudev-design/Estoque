/// PaymentSpeciesRepository — Cache local de formas de pagamento.
///
/// Lê do cache SQLite (`payment_species` table).
/// Populado pelo SyncService via pull periódico do Worker.
///
/// REGRA (Rule-06 Clean Architecture): Lógica de negócio fica no
/// CartNotifier. Este repo é infraestrutura pura de acesso a dados.
library;

import '../database/database_helper.dart';
import 'models/payment_species.dart';

class PaymentSpeciesRepository {
  final DatabaseHelper _db;

  PaymentSpeciesRepository({required DatabaseHelper db}) : _db = db;

  // ───────────────────────────────────────────────────────────────────────────
  // Leitura
  // ───────────────────────────────────────────────────────────────────────────

  /// Retorna todas as espécies de pagamento do cache local, ordenadas por nome.
  ///
  /// Retorna lista vazia se nenhuma espécie tiver sido sincronizada ainda.
  Future<List<PaymentSpecies>> getAll() async {
    final db   = await _db.database;
    final rows = await db.query(
      'payment_species',
      orderBy: 'name ASC',
    );
    return rows.map(PaymentSpecies.fromMap).toList();
  }

  /// Retorna uma espécie pelo [id]. Retorna null se não encontrada.
  Future<PaymentSpecies?> getById(String id) async {
    final db   = await _db.database;
    final rows = await db.query(
      'payment_species',
      where: 'payment_species_id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return PaymentSpecies.fromMap(rows.first);
  }

  /// Quantidade de espécies em cache.
  Future<int> count() async {
    final db  = await _db.database;
    final res = await db.rawQuery('SELECT COUNT(*) as c FROM payment_species');
    return (res.first['c'] as int?) ?? 0;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Escrita (somente pelo SyncService — nunca pelo frontend diretamente)
  // ───────────────────────────────────────────────────────────────────────────

  /// Atualiza o cache local em batch. Chamado pelo SyncService após pull.
  ///
  /// @param species  Lista de espécies recebidas da API.
  Future<void> upsertBatch(List<PaymentSpecies> species) async {
    await _db.upsertPaymentSpeciesBatch(
      species.map((s) => s.toMap()).toList(),
    );
  }
}

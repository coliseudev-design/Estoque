/// NaturezaOperacaoRepository — Cache local de naturezas de operação.
///
/// Lê da tabela `natureza_operacao` no SQLite local.
/// Populado pelo SyncService via pull do Worker (NATUREZA_OPERACAO WHERE MOB_ACESSO='S').
library;

import '../database/database_helper.dart';
import 'models/natureza_operacao.dart';

class NaturezaOperacaoRepository {
  final DatabaseHelper _db;

  NaturezaOperacaoRepository({required DatabaseHelper db}) : _db = db;

  /// Retorna todas as naturezas com acesso ao app, ordenadas por mob_ordem.
  Future<List<NaturezaOperacao>> getAll() async {
    final db   = await _db.database;
    final rows = await db.query(
      'natureza_operacao',
      orderBy: 'mob_ordem ASC, descricao ASC',
    );
    return rows.map(NaturezaOperacao.fromMap).toList();
  }

  /// Retorna uma natureza pelo [id]. Retorna null se não encontrada.
  Future<NaturezaOperacao?> getById(String id) async {
    final db   = await _db.database;
    final rows = await db.query(
      'natureza_operacao',
      where: 'natureza_id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return NaturezaOperacao.fromMap(rows.first);
  }

  /// Quantidade de naturezas em cache.
  Future<int> count() async {
    final db  = await _db.database;
    final res = await db.rawQuery('SELECT COUNT(*) as c FROM natureza_operacao');
    return (res.first['c'] as int?) ?? 0;
  }

  /// Atualiza o cache em batch — chamado pelo SyncService.
  Future<void> upsertBatch(List<NaturezaOperacao> naturezas) async {
    await _db.upsertNaturezaBatch(
      naturezas.map((n) => n.toMap()).toList(),
    );
  }
}

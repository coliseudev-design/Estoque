/// FinancialRepository — Acesso aos títulos financeiros (contas a receber) do SQLite local.
///
/// Dados vêm da tabela MOB_LISTACONTAS do Firebird, sincronizados via
/// Worker → VPS API → Flutter.
///
/// Regra (Clean Architecture): apenas queries e mapeamento de dados.
library;

import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';

/// Título financeiro (conta a receber) de um cliente.
class Financial {
  final String  id;
  final String  customerId;
  final String? docNumber;
  final double  amount;
  final double  interest;
  final String? dueDate;
  final bool    isPaid;
  final String? type;
  final String? paymentDate;

  const Financial({
    required this.id,
    required this.customerId,
    this.docNumber,
    required this.amount,
    this.interest = 0,
    this.dueDate,
    this.isPaid = false,
    this.type,
    this.paymentDate,
  });

  /// Valor total (principal + juros).
  double get total => amount + interest;

  /// True se o título está vencido e não pago.
  bool get isOverdue {
    if (isPaid || dueDate == null) return false;
    final due = DateTime.tryParse(dueDate!);
    if (due == null) return false;
    return due.isBefore(DateTime.now());
  }

  factory Financial.fromMap(Map<String, dynamic> map) => Financial(
        id:          map['id']            as String,
        customerId:  map['customer_id']   as String,
        docNumber:   map['doc_number']    as String?,
        amount:      (map['amount']       as num? ?? 0).toDouble(),
        interest:    (map['interest']     as num? ?? 0).toDouble(),
        dueDate:     map['due_date']      as String?,
        isPaid:      (map['is_paid']      as int? ?? 0) == 1,
        type:        map['type']          as String?,
        paymentDate: map['payment_date']  as String?,
      );
}

class FinancialRepository {
  final DatabaseHelper _db;

  FinancialRepository({required DatabaseHelper db}) : _db = db;

  /// Retorna todos os títulos em aberto de um cliente.
  ///
  /// @param customerId  ID do cliente (chave de foreign key).
  /// @param onlyOpen    Se true, retorna apenas os não pagos. Padrão true.
  Future<List<Financial>> getByCustomer(
    String customerId, {
    bool onlyOpen = true,
  }) async {
    final db    = await _db.database;
    final where = onlyOpen
        ? 'customer_id = ? AND is_paid = 0'
        : 'customer_id = ?';

    final rows = await db.query(
      'financials',
      where:     where,
      whereArgs: [customerId],
      orderBy:   'due_date ASC',
    );
    return rows.map(Financial.fromMap).toList();
  }

  /// Soma total de valores em aberto do cliente.
  Future<double> totalOpenByCustomer(String customerId) async {
    final db     = await _db.database;
    final result = await db.rawQuery(
      'SELECT SUM(amount + interest) as total FROM financials WHERE customer_id = ? AND is_paid = 0',
      [customerId],
    );
    return (result.first['total'] as num? ?? 0).toDouble();
  }

  /// Conta quantos títulos em aberto e quantos vencidos.
  Future<({int open, int overdue})> countByCustomer(String customerId) async {
    final open = await getByCustomer(customerId);
    final ov   = open.where((f) => f.isOverdue).length;
    return (open: open.length, overdue: ov);
  }

  /// Upsert em batch — chamado pelo SyncService após pullFinancials().
  Future<void> upsertBatch(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    final db    = await _db.database;
    final batch = db.batch();
    for (final r in rows) {
      batch.insert('financials', r, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }
}

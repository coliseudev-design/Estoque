import '../database/database_helper.dart';
import 'models/payment_condition.dart';

class PaymentConditionRepository {
  final DatabaseHelper _dbHelper;

  PaymentConditionRepository(this._dbHelper);

  Future<void> replaceAll(List<PaymentCondition> conditions) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      await txn.delete('payment_conditions');
      for (var condition in conditions) {
        await txn.insert('payment_conditions', condition.toMap());
      }
    });
  }

  Future<List<PaymentCondition>> getAll() async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'payment_conditions',
      orderBy: 'mob_ordem ASC',
    );
    return List.generate(maps.length, (i) => PaymentCondition.fromMap(maps[i]));
  }

  /// Retorna condições de pagamento vinculadas a uma espécie de pagamento.
  ///
  /// Se o banco não tiver o campo especie_id preenchido (sync antiga sem o campo),
  /// retorna todas as condições como fallback para garantir retrocompatibilidade.
  ///
  /// @param specieId  ID da espécie selecionada na tela de pedido.
  /// @returns         Lista filtrada, ou todas as condições se nenhuma tiver vínculo.
  Future<List<PaymentCondition>> getBySpecies(String specieId) async {
    final all = await getAll();
    final filtered = all.where((c) => c.specieId == specieId).toList();
    // Retrocompatibilidade: se nenhuma condição tem especie_id, mostra todas
    return filtered.isEmpty ? all : filtered;
  }
}

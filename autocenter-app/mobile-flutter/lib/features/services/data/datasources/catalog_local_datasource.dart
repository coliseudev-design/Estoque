import 'package:sqflite/sqflite.dart';
import '../../../../../core/database/database_helper.dart';
import '../models/catalog_item_model.dart';
import '../models/payment_species_model.dart';
import '../models/payment_condition_model.dart';
import '../models/natureza_model.dart';

class CatalogLocalDataSource {
  Future<void> replaceCatalogBatch(List<CatalogItemModel> items) async {
    if (items.isEmpty) return;
    final db = await DatabaseHelper.instance.database;

    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final item in items) {
        batch.insert(
          'catalog',
          item.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> replacePaymentSpeciesBatch(List<PaymentSpeciesModel> items) async {
    if (items.isEmpty) return;
    final db = await DatabaseHelper.instance.database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final item in items) {
        batch.insert(
          'payment_species',
          item.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> replacePaymentConditionsBatch(List<PaymentConditionModel> items) async {
    if (items.isEmpty) return;
    final db = await DatabaseHelper.instance.database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final item in items) {
        batch.insert(
          'payment_conditions',
          item.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> replaceNaturezasBatch(List<NaturezaModel> items) async {
    if (items.isEmpty) return;
    final db = await DatabaseHelper.instance.database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final item in items) {
        batch.insert(
          'naturezas_operacao',
          item.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<PaymentSpeciesModel>> getPaymentSpecies() async {
    final db = await DatabaseHelper.instance.database;
    final res = await db.query('payment_species', orderBy: 'description ASC');
    return res.map((e) => PaymentSpeciesModel.fromMap(e)).toList();
  }

  Future<List<PaymentConditionModel>> getPaymentConditions() async {
    final db = await DatabaseHelper.instance.database;
    final res = await db.query('payment_conditions', orderBy: 'descricao ASC');
    return res.map((e) => PaymentConditionModel.fromMap(e)).toList();
  }

  Future<List<NaturezaModel>> getNaturezas() async {
    final db = await DatabaseHelper.instance.database;
    final res = await db.query('naturezas_operacao', orderBy: 'mob_ordem ASC, descricao ASC');
    return res.map((e) => NaturezaModel.fromMap(e)).toList();
  }

  Future<List<CatalogItemModel>> getCatalogByCategory(String category) async {
    final db = await DatabaseHelper.instance.database;
    final res = await db.query(
      'catalog',
      where: 'category = ? AND active = 1',
      whereArgs: [category],
      orderBy: 'name ASC',
    );
    return res.map((e) => CatalogItemModel.fromMap(e)).toList();
  }

  Future<List<String>> getCategories() async {
    final db = await DatabaseHelper.instance.database;
    final res = await db.rawQuery('SELECT DISTINCT category FROM catalog WHERE active = 1 ORDER BY category ASC');
    return res
        .map((e) => e['category']?.toString() ?? 'Geral')
        .where((cat) => cat.isNotEmpty)
        .toSet()
        .toList();
  }

  Future<List<CatalogItemModel>> getAllCatalog() async {
    final db = await DatabaseHelper.instance.database;
    final res = await db.query(
      'catalog',
      where: 'active = 1',
      orderBy: 'category ASC, name ASC',
    );
    return res.map((e) => CatalogItemModel.fromMap(e)).toList();
  }

  Future<List<CatalogItemModel>> searchCatalog(String query) async {
    final db = await DatabaseHelper.instance.database;
    final searchPattern = '%$query%';
    final res = await db.query(
      'catalog',
      where: 'active = 1 AND (name LIKE ? OR code LIKE ?)',
      whereArgs: [searchPattern, searchPattern],
      orderBy: 'name ASC, category ASC',
      limit: 100,
    );
    return res.map((e) => CatalogItemModel.fromMap(e)).toList();
  }

  Future<int> getCatalogCount() async {
    final db = await DatabaseHelper.instance.database;
    final res = await db.rawQuery('SELECT COUNT(*) AS count FROM catalog WHERE active = 1');
    return Sqflite.firstIntValue(res) ?? 0;
  }
}

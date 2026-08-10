import 'package:sqflite/sqflite.dart';
import '../../../../core/database/database_helper.dart';
import '../models/technician_model.dart';

class TechnicianLocalDataSource {
  final DatabaseHelper _dbHelper;

  TechnicianLocalDataSource({DatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  Future<void> replaceTechniciansBatch(List<TechnicianModel> technicians) async {
    final db = await _dbHelper.database;

    await db.transaction((txn) async {
      final batch = txn.batch();
      for (var tech in technicians) {
        batch.insert(
          'technicians',
          tech.toSqlMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<TechnicianModel>> getAllTechnicians() async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'technicians',
      where: 'active = 1',
      orderBy: 'name ASC',
    );
    return maps.map((m) => TechnicianModel.fromSqlMap(m)).toList();
  }
}

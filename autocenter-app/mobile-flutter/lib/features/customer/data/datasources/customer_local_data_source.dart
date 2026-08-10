import 'package:sqflite/sqflite.dart';
import '../../../../core/database/database_helper.dart';
import '../models/customer_model.dart';

class CustomerLocalDataSource {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<void> clearCustomers() async {
    final db = await _dbHelper.database;
    await db.delete('customers');
  }

  Future<void> insertBatch(List<CustomerModel> customers) async {
    final db = await _dbHelper.database;
    
    // SQLite batch insertion para performance optimal
    Batch batch = db.batch();
    for (var customer in customers) {
      batch.insert(
        'customers', 
        customer.toJson(),
        conflictAlgorithm: ConflictAlgorithm.replace // UPSERT
      );
    }
    await batch.commit(noResult: true);
  }

  Future<int> insertCustomer(CustomerModel customer) async {
    final db = await _dbHelper.database;
    return await db.insert(
      'customers',
      customer.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<CustomerModel>> searchCustomers(String query) async {
    final db = await _dbHelper.database;
    final searchPattern = '%$query%';
    
    final List<Map<String, dynamic>> maps = await db.query(
      'customers',
      where: 'active = 1 AND (name LIKE ? OR cpf_cnpj LIKE ? OR phone LIKE ? OR local_id LIKE ?)',
      whereArgs: [searchPattern, searchPattern, searchPattern, searchPattern],
      orderBy: 'name ASC',
      limit: 50,
    );

    return maps.map((map) => CustomerModel.fromSqlMap(map)).toList();
  }
  
  Future<CustomerModel?> getCustomerByErpId(int erpId) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'customers',
      where: 'erp_id = ?',
      whereArgs: [erpId],
    );

    if (maps.isNotEmpty) {
      return CustomerModel.fromSqlMap(maps.first);
    }
    return null;
  }

  Future<CustomerModel?> getCustomerByLocalId(String localId) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'customers',
      where: 'local_id = ?',
      whereArgs: [localId],
    );

    if (maps.isNotEmpty) {
      return CustomerModel.fromSqlMap(maps.first);
    }
    return null;
  }

  Future<void> updateCustomerSyncStatus(String localId, int erpId, String syncStatus) async {
    final db = await _dbHelper.database;
    await db.update(
      'customers',
      {
        'erp_id': erpId,
        'sync_status': syncStatus,
      },
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  Future<List<CustomerModel>> getPendingCustomers() async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'customers',
      where: 'sync_status = ?',
      whereArgs: ['pending'],
    );
    return maps.map((map) => CustomerModel.fromSqlMap(map)).toList();
  }

  Future<int> getCustomerCount() async {
    final db = await _dbHelper.database;
    final res = await db.rawQuery('SELECT COUNT(*) AS count FROM customers WHERE active = 1');
    return Sqflite.firstIntValue(res) ?? 0;
  }
}

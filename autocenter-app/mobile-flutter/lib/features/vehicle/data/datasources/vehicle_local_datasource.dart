import 'package:sqflite/sqflite.dart';
import '../../../../core/database/database_helper.dart';
import '../../domain/entities/vehicle.dart';

abstract class VehicleLocalDataSource {
  Future<Vehicle?> getVehicleByPlate(String plate);
  Future<void> cacheVehicle(Vehicle vehicle);
  Future<void> cacheVehicles(List<Vehicle> vehicles);
  Future<void> clearPlate(String plate);
  Future<List<Vehicle>> getVehiclesByCustomerId(int customerId);
}

class VehicleLocalDataSourceImpl implements VehicleLocalDataSource {
  final DatabaseHelper dbHelper;

  VehicleLocalDataSourceImpl({required this.dbHelper});

  @override
  Future<Vehicle?> getVehicleByPlate(String plate) async {
    final db = await dbHelper.database;
    final maps = await db.query(
      'vehicles',
      where: 'plate = ?',
      whereArgs: [plate],
    );
    if (maps.isNotEmpty) {
      return Vehicle.fromMap(maps.first);
    }
    return null;
  }

  @override
  Future<void> cacheVehicle(Vehicle vehicle) async {
    final db = await dbHelper.database;
    // REPLACE: if plate already exists, overwrite with fresh data
    await db.insert(
      'vehicles',
      vehicle.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> cacheVehicles(List<Vehicle> vehicles) async {
    final db = await dbHelper.database;
    final batch = db.batch();
    for (var vehicle in vehicles) {
      batch.insert(
        'vehicles',
        vehicle.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  @override
  Future<void> clearPlate(String plate) async {
    final db = await dbHelper.database;
    await db.delete('vehicles', where: 'plate = ?', whereArgs: [plate]);
  }

  @override
  Future<List<Vehicle>> getVehiclesByCustomerId(int customerId) async {
    final db = await dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'vehicles',
      where: 'id_cliente = ?',
      whereArgs: [customerId],
    );
    return maps.map((map) => Vehicle.fromMap(map)).toList();
  }
}

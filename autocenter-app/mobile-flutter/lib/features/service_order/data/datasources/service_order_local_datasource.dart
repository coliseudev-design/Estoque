import 'package:sqflite/sqflite.dart';
import '../../../../core/database/database_helper.dart';
import '../models/service_order_model.dart';
import '../../domain/entities/service_order.dart';

class ServiceOrderLocalDataSource {
  final DatabaseHelper _dbHelper;

  ServiceOrderLocalDataSource({DatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  Future<void> insertServiceOrder(ServiceOrderModel os) async {
    final db = await _dbHelper.database;

    await db.transaction((txn) async {
      // 1. Insert order
      await txn.insert(
        'service_orders',
        os.toSqlMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // 2. Insert items
      for (var item in os.items) {
        final itemModel = ServiceOrderItemModel.fromEntity(item);
        await txn.insert(
          'service_order_items',
          itemModel.toSqlMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      // 3. Insert photos
      for (var photo in os.photos) {
        final photoModel = ServiceOrderPhotoModel.fromEntity(photo);
        await txn.insert(
          'service_order_photos',
          photoModel.toSqlMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      // 4. Insert checklist items
      for (var check in os.checklist) {
        final checklistModel = ServiceOrderChecklistModel.fromEntity(check);
        await txn.insert(
          'service_order_checklist',
          checklistModel.toSqlMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<List<ServiceOrderModel>> listServiceOrders({String? status, String? plate}) async {
    final db = await _dbHelper.database;

    String whereClause = '1 = 1';
    List<dynamic> whereArgs = [];

    if (status != null && status.isNotEmpty) {
      whereClause += ' AND status = ?';
      whereArgs.add(status);
    }

    if (plate != null && plate.isNotEmpty) {
      whereClause += ' AND plate LIKE ?';
      whereArgs.add('%$plate%');
    }

    final List<Map<String, dynamic>> orderMaps = await db.query(
      'service_orders',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'created_at DESC',
    );

    List<ServiceOrderModel> results = [];
    for (var map in orderMaps) {
      final String id = map['id'] as String;

      // Fetch items
      final List<Map<String, dynamic>> itemMaps = await db.query(
        'service_order_items',
        where: 'service_order_id = ?',
        whereArgs: [id],
      );
      final items = itemMaps.map((m) => ServiceOrderItemModel.fromSqlMap(m)).toList();

      // Fetch photos
      final List<Map<String, dynamic>> photoMaps = await db.query(
        'service_order_photos',
        where: 'service_order_id = ?',
        whereArgs: [id],
      );
      final photos = photoMaps.map((m) => ServiceOrderPhotoModel.fromSqlMap(m)).toList();

      // Fetch checklist
      final List<Map<String, dynamic>> checklistMaps = await db.query(
        'service_order_checklist',
        where: 'service_order_id = ?',
        whereArgs: [id],
      );
      final checklist = checklistMaps.map((m) => ServiceOrderChecklistModel.fromSqlMap(m)).toList();

      results.add(ServiceOrderModel.fromSqlMap(
        map,
        items: items,
        photos: photos,
        checklist: checklist,
      ));
    }

    return results;
  }

  Future<ServiceOrderModel?> getServiceOrderById(String id) async {
    final db = await _dbHelper.database;

    final List<Map<String, dynamic>> orderMaps = await db.query(
      'service_orders',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (orderMaps.isEmpty) return null;

    // Fetch items
    final List<Map<String, dynamic>> itemMaps = await db.query(
      'service_order_items',
      where: 'service_order_id = ?',
      whereArgs: [id],
    );
    final items = itemMaps.map((m) => ServiceOrderItemModel.fromSqlMap(m)).toList();

    // Fetch photos
    final List<Map<String, dynamic>> photoMaps = await db.query(
      'service_order_photos',
      where: 'service_order_id = ?',
      whereArgs: [id],
    );
    final photos = photoMaps.map((m) => ServiceOrderPhotoModel.fromSqlMap(m)).toList();

    // Fetch checklist
    final List<Map<String, dynamic>> checklistMaps = await db.query(
      'service_order_checklist',
      where: 'service_order_id = ?',
      whereArgs: [id],
    );
    final checklist = checklistMaps.map((m) => ServiceOrderChecklistModel.fromSqlMap(m)).toList();

    return ServiceOrderModel.fromSqlMap(
      orderMaps.first,
      items: items,
      photos: photos,
      checklist: checklist,
    );
  }

  Future<void> updateServiceOrderStatus(String id, String status, {String? syncStatus}) async {
    final db = await _dbHelper.database;
    final Map<String, dynamic> values = {
      'status': status,
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (syncStatus != null) {
      values['sync_status'] = syncStatus;
    }

    await db.update(
      'service_orders',
      values,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> insertBatch(List<ServiceOrderModel> orders) async {
    final db = await _dbHelper.database;

    await db.transaction((txn) async {
      for (var os in orders) {
        await txn.insert(
          'service_orders',
          os.toSqlMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        // Delete existing items/photos/checklist to overwrite
        await txn.delete('service_order_items', where: 'service_order_id = ?', whereArgs: [os.id]);
        await txn.delete('service_order_photos', where: 'service_order_id = ?', whereArgs: [os.id]);
        await txn.delete('service_order_checklist', where: 'service_order_id = ?', whereArgs: [os.id]);

        for (var item in os.items) {
          final itemModel = ServiceOrderItemModel.fromEntity(item);
          await txn.insert('service_order_items', itemModel.toSqlMap());
        }

        for (var photo in os.photos) {
          final photoModel = ServiceOrderPhotoModel.fromEntity(photo);
          await txn.insert('service_order_photos', photoModel.toSqlMap());
        }

        for (var check in os.checklist) {
          final checklistModel = ServiceOrderChecklistModel.fromEntity(check);
          await txn.insert('service_order_checklist', checklistModel.toSqlMap());
        }
      }
    });
  }

  Future<List<ServiceOrderModel>> getPendingServiceOrders() async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> orderMaps = await db.query(
      'service_orders',
      where: 'sync_status = ?',
      whereArgs: ['pending'],
    );

    List<ServiceOrderModel> results = [];
    for (var map in orderMaps) {
      final String id = map['id'] as String;

      final List<Map<String, dynamic>> itemMaps = await db.query(
        'service_order_items',
        where: 'service_order_id = ?',
        whereArgs: [id],
      );
      final items = itemMaps.map((m) => ServiceOrderItemModel.fromSqlMap(m)).toList();

      final List<Map<String, dynamic>> photoMaps = await db.query(
        'service_order_photos',
        where: 'service_order_id = ?',
        whereArgs: [id],
      );
      final photos = photoMaps.map((m) => ServiceOrderPhotoModel.fromSqlMap(m)).toList();

      final List<Map<String, dynamic>> checklistMaps = await db.query(
        'service_order_checklist',
        where: 'service_order_id = ?',
        whereArgs: [id],
      );
      final checklist = checklistMaps.map((m) => ServiceOrderChecklistModel.fromSqlMap(m)).toList();

      results.add(ServiceOrderModel.fromSqlMap(
        map,
        items: items,
        photos: photos,
        checklist: checklist,
      ));
    }

    return results;
  }

  Future<void> insertServiceOrderPhoto(ServiceOrderPhoto photo) async {
    final db = await _dbHelper.database;
    final model = ServiceOrderPhotoModel.fromEntity(photo);
    await db.insert(
      'service_order_photos',
      model.toSqlMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // Mark OS as pending for sync
    await db.update(
      'service_orders',
      {
        'sync_status': 'pending',
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [photo.serviceOrderId],
    );
  }
}

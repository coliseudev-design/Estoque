import '../../../../core/database/database_helper.dart';
import '../../domain/entities/draft.dart';
import '../../../../core/network/sync_service.dart';

class DraftLocalDataSource {
  final DatabaseHelper dbHelper;

  DraftLocalDataSource({required this.dbHelper});

  Future<int> insertDraft(Draft draft, List<DraftPhoto> photos, List<DraftItem> items) async {
    final db = await dbHelper.database;
    
    int draftId = 0;
    
    // Transação para garantir consistência entre rascunho, fotos e itens do carrinho
    await db.transaction((txn) async {
      draftId = await txn.insert('drafts', draft.toMap());
      
      for (var photo in photos) {
        final photoMap = photo.toMap();
        photoMap['draft_id'] = draftId; // Vincula ID gerado
        await txn.insert('draft_photos', photoMap);
      }

      for (var item in items) {
        final itemMap = item.toMap();
        itemMap['draft_id'] = draftId;
        await txn.insert('draft_items', itemMap);
      }

      // Adicionar à fila de sincronização (sync_queue)
      await txn.insert('sync_queue', {
        'item_type': 'draft',
        'item_id': draftId.toString(),
        'operation': 'CREATE',
        'payload': '{}',
        'status': 'PENDING',
        'attempts': 0,
        'created_at': DateTime.now().toIso8601String(),
      });
    });

    // Dispara worker (WorkManager) para tentar sincronia aqui.
    SyncService.registerOfflineSync();
    return draftId;
  }

  Future<List<Draft>> getPendingDrafts() async {
    final db = await dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'drafts',
      where: 'status = ?',
      whereArgs: ['PENDENTE_SYNC'],
    );

    return List.generate(maps.length, (i) {
      return Draft(
        id: maps[i]['id'],
        vehiclePlate: maps[i]['vehicle_plate'],
        customerName: maps[i]['customer_name'],
        status: maps[i]['status'],
        createdAt: maps[i]['created_at'],
      );
    });
  }

  Future<List<DraftItem>> getDraftItems(int draftId) async {
    final db = await dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'draft_items',
      where: 'draft_id = ?',
      whereArgs: [draftId],
    );

    return List.generate(maps.length, (i) {
      return DraftItem(
        id: maps[i]['id'],
        draftId: maps[i]['draft_id'],
        productCode: maps[i]['product_code'],
        productName: maps[i]['product_name'] ?? 'Desconhecido',
        quantity: maps[i]['quantity'],
        unitPrice: maps[i]['unit_price'],
        discount: maps[i]['discount'],
      );
    });
  }

  Future<void> updateDraftStatus(int draftId, String newStatus) async {
    final db = await dbHelper.database;
    await db.update(
      'drafts',
      {'status': newStatus},
      where: 'id = ?',
      whereArgs: [draftId],
    );
  }

  Future<List<String>> getDraftPhotos(int draftId) async {
    final db = await dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'draft_photos',
      columns: ['path'],
      where: 'draft_id = ?',
      whereArgs: [draftId],
    );

    return maps.map((m) => m['path'] as String).toList();
  }
}

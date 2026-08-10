import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../../features/customer/data/datasources/customer_local_data_source.dart';
import '../../features/customer/data/datasources/customer_remote_data_source.dart';
import '../../features/customer/data/models/customer_model.dart';
import '../../features/draft/data/datasources/draft_local_datasource.dart';
import '../../features/draft/data/datasources/draft_remote_datasource.dart';
import '../../features/draft/domain/entities/draft.dart';
import '../../features/service_order/data/datasources/service_order_local_datasource.dart';
import '../../features/service_order/data/datasources/service_order_remote_datasource.dart';
import '../../features/service_order/data/models/service_order_model.dart';
import '../../features/service_order/data/datasources/technician_local_datasource.dart';
import '../../features/service_order/data/datasources/technician_remote_datasource.dart';

class SyncQueueService {
  static final SyncQueueService instance = SyncQueueService._init();
  SyncQueueService._init();

  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<void> queueItem({
    required String itemType,
    required String itemId,
    required String operation,
    required Map<String, dynamic> payload,
  }) async {
    final db = await _dbHelper.database;
    await db.insert('sync_queue', {
      'item_type': itemType,
      'item_id': itemId,
      'operation': operation,
      'payload': jsonEncode(payload),
      'status': 'PENDING',
      'attempts': 0,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> processQueue() async {
    final db = await _dbHelper.database;
    
    // Check connectivity first
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.contains(ConnectivityResult.none)) {
      print('[SyncQueueService] Sem conexão de internet. Ignorando processamento.');
      return;
    }

    final List<Map<String, dynamic>> pendingItems = await db.query(
      'sync_queue',
      where: 'status = ? OR status = ?',
      whereArgs: ['PENDING', 'FAILED'],
      orderBy: 'id ASC',
    );

    if (pendingItems.isEmpty) {
      print('[SyncQueueService] Fila de sincronização vazia.');
      await syncTechnicians();
      return;
    }

    print('[SyncQueueService] Processando ${pendingItems.length} itens na fila...');

    for (var item in pendingItems) {
      final int queueId = item['id'] as int;
      final String itemType = item['item_type'] as String;
      final String itemId = item['item_id'] as String;
      final String operation = item['operation'] as String;
      final Map<String, dynamic> payload = jsonDecode(item['payload'] as String) as Map<String, dynamic>;
      final int attempts = item['attempts'] as int;

      await db.update(
        'sync_queue',
        {
          'status': 'SYNCING',
          'attempts': attempts + 1,
        },
        where: 'id = ?',
        whereArgs: [queueId],
      );

      try {
        if (itemType == 'customer') {
          await _syncCustomerItem(itemId, operation, payload);
        } else if (itemType == 'draft') {
          await _syncDraftItem(int.parse(itemId), operation, payload);
        } else if (itemType == 'service_order') {
          await _syncServiceOrderItem(itemId, operation, payload);
        } else if (itemType == 'service_order_status') {
          await _syncServiceOrderStatusItem(itemId, operation, payload);
        }

        // Mark as Success
        await db.update(
          'sync_queue',
          {
            'status': 'SUCCESS',
          },
          where: 'id = ?',
          whereArgs: [queueId],
        );
        print('[SyncQueueService] Item $queueId ($itemType:$itemId) sincronizado com sucesso.');
      } catch (e) {
        print('[SyncQueueService] Falha ao sincronizar item $queueId: $e');
        await db.update(
          'sync_queue',
          {
            'status': 'FAILED',
            'error_message': e.toString(),
          },
          where: 'id = ?',
          whereArgs: [queueId],
        );
      }
    }
    await syncTechnicians();
  }

  Future<void> _syncCustomerItem(String localId, String operation, Map<String, dynamic> payload) async {
    final localDataSource = CustomerLocalDataSource();
    final remoteDataSource = CustomerRemoteDataSource();

    final customer = await localDataSource.getCustomerByLocalId(localId);
    if (customer == null) {
      throw Exception('Cliente local não encontrado no SQLite: $localId');
    }

    if (customer.syncStatus == 'synced' && customer.erpId != null) {
      print('[SyncQueueService] Cliente $localId já está sincronizado.');
      return;
    }

    // Call remote API
    final syncedCustomer = await remoteDataSource.createCustomer(customer);
    
    // Update local database with ERP ID and status 'synced'
    if (syncedCustomer.erpId != null) {
      await localDataSource.updateCustomerSyncStatus(localId, syncedCustomer.erpId!, 'synced');
    } else {
      throw Exception('Middleware não retornou um ERP ID válido.');
    }
  }

  Future<void> _syncDraftItem(int draftId, String operation, Map<String, dynamic> payload) async {
    final localDataSource = DraftLocalDataSource(dbHelper: _dbHelper);
    final remoteDataSource = DraftRemoteDataSource();

    // Encontra o rascunho independentemente do status para sincronizar
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'drafts',
      where: 'id = ?',
      whereArgs: [draftId],
    );

    if (maps.isEmpty) {
      throw Exception('Rascunho não encontrado localmente: $draftId');
    }

    final draft = Draft(
      id: maps.first['id'],
      vehiclePlate: maps.first['vehicle_plate'],
      customerName: maps.first['customer_name'],
      status: maps.first['status'],
      createdAt: maps.first['created_at'],
    );

    final items = await localDataSource.getDraftItems(draftId);
    final photos = await localDataSource.getDraftPhotos(draftId);

    final quoteIdOrError = await remoteDataSource.pushDraft(draft, items);

    if (quoteIdOrError != null) {
      bool photosSuccess = true;
      if (quoteIdOrError != '409_DUPLICADO' && photos.isNotEmpty) {
        photosSuccess = await remoteDataSource.pushPhotos(quoteIdOrError, photos);
      }

      if (photosSuccess || quoteIdOrError == '409_DUPLICADO') {
        await localDataSource.updateDraftStatus(draftId, 'SINCRONIZADO');
        // Clear local photo and item tables for this draft to save space
        await db.delete('draft_photos', where: 'draft_id = ?', whereArgs: [draftId]);
        await db.delete('draft_items', where: 'draft_id = ?', whereArgs: [draftId]);
      } else {
        throw Exception('Falha ao enviar fotos associadas ao rascunho.');
      }
    } else {
      throw Exception('Erro ao enviar o rascunho de venda ao middleware.');
    }
  }

  Future<void> _syncServiceOrderItem(String osId, String operation, Map<String, dynamic> payload) async {
    final localDataSource = ServiceOrderLocalDataSource();
    final remoteDataSource = ServiceOrderRemoteDataSource();

    final os = await localDataSource.getServiceOrderById(osId);
    if (os == null) {
      throw Exception('Ordem de Serviço local não encontrada no SQLite: $osId');
    }

    if (os.syncStatus == 'synced') {
      print('[SyncQueueService] OS $osId já está sincronizada.');
      return;
    }

    // Envia a OS remotamente
    final syncedOs = await remoteDataSource.createServiceOrder(os);
    if (syncedOs != null) {
      // Sincroniza fotos locais ao middleware se houver
      final localPhotos = os.photos.map((p) => p.photoUrl).toList();
      if (localPhotos.isNotEmpty) {
        final photosSuccess = await remoteDataSource.uploadPhotos(osId, localPhotos);
        if (!photosSuccess) {
          print('[SyncQueueService] Aviso: Algumas fotos falharam ao subir para a OS $osId.');
        }
      }

      // Atualiza status local para 'synced'
      await localDataSource.updateServiceOrderStatus(osId, os.status, syncStatus: 'synced');
    } else {
      throw Exception('Middleware não conseguiu criar a Ordem de Serviço.');
    }
  }

  Future<void> _syncServiceOrderStatusItem(String osId, String operation, Map<String, dynamic> payload) async {
    final localDataSource = ServiceOrderLocalDataSource();
    final remoteDataSource = ServiceOrderRemoteDataSource();

    final String status = payload['status'] as String;

    final success = await remoteDataSource.updateStatus(osId, status);
    if (success) {
      await localDataSource.updateServiceOrderStatus(osId, status, syncStatus: 'synced');
    } else {
      throw Exception('Falha ao atualizar status da OS no Middleware.');
    }
  }

  Future<void> syncTechnicians() async {
    try {
      print('[SyncQueueService] Buscando técnicos do middleware...');
      final remoteDataSource = TechnicianRemoteDataSource();
      final localDataSource = TechnicianLocalDataSource();
      final remoteList = await remoteDataSource.getTechnicians();
      if (remoteList.isNotEmpty) {
        await localDataSource.replaceTechniciansBatch(remoteList);
        print('[SyncQueueService] ${remoteList.length} técnicos atualizados localmente.');
      }
    } catch (e) {
      print('[SyncQueueService] Erro ao sincronizar técnicos: $e');
    }
  }

  Future<Map<String, int>> getSyncQueueStats() async {
    try {
      final db = await _dbHelper.database;
      final List<Map<String, dynamic>> pendingRes = await db.rawQuery(
        "SELECT COUNT(*) as count FROM sync_queue WHERE status = 'PENDING'"
      );
      final List<Map<String, dynamic>> failedRes = await db.rawQuery(
        "SELECT COUNT(*) as count FROM sync_queue WHERE status = 'FAILED'"
      );
      return {
        'pending': pendingRes.first['count'] as int? ?? 0,
        'failed': failedRes.first['count'] as int? ?? 0,
      };
    } catch (_) {
      return {'pending': 0, 'failed': 0};
    }
  }

  Future<void> syncSingleServiceOrder(String osId) async {
    final db = await _dbHelper.database;
    
    final List<Map<String, dynamic>> items = await db.query(
      'sync_queue',
      where: "item_type = 'service_order' AND item_id = ?",
      whereArgs: [osId],
    );
    
    if (items.isEmpty) {
      throw Exception('Nenhum item de sincronização encontrado na fila local para esta OS (ID: $osId).');
    }
    
    final item = items.first;
    final int queueId = item['id'] as int;
    final String itemType = item['item_type'] as String;
    final String itemId = item['item_id'] as String;
    final String operation = item['operation'] as String;
    final Map<String, dynamic> payload = jsonDecode(item['payload'] as String) as Map<String, dynamic>;
    
    await db.update(
      'sync_queue',
      {'status': 'SYNCING'},
      where: 'id = ?',
      whereArgs: [queueId],
    );
    
    try {
      final localOS = await ServiceOrderLocalDataSource().getServiceOrderById(osId);
      if (localOS != null) {
        final List<Map<String, dynamic>> pendingCustomers = await db.query(
          'sync_queue',
          where: "item_type = 'customer' AND (status = 'PENDING' OR status = 'FAILED')",
        );
        for (var pc in pendingCustomers) {
          final pcId = pc['id'] as int;
          final pcLocalId = pc['item_id'] as String;
          final pcPayload = jsonDecode(pc['payload'] as String) as Map<String, dynamic>;
          if (pcPayload['name'] == localOS.customerName) {
            await db.update('sync_queue', {'status': 'SYNCING'}, where: 'id = ?', whereArgs: [pcId]);
            try {
              await _syncCustomerItem(pcLocalId, pc['operation'] as String, pcPayload);
              await db.update('sync_queue', {'status': 'SUCCESS'}, where: 'id = ?', whereArgs: [pcId]);
            } catch (custErr) {
              await db.update(
                'sync_queue',
                {'status': 'FAILED', 'error_message': custErr.toString()},
                where: 'id = ?',
                whereArgs: [pcId],
              );
              throw Exception('Falha ao sincronizar o cliente associado (${localOS.customerName}): $custErr');
            }
          }
        }
      }

      await _syncServiceOrderItem(osId, operation, payload);
      
      await db.update(
        'sync_queue',
        {'status': 'SUCCESS'},
        where: 'id = ?',
        whereArgs: [queueId],
      );
    } catch (e) {
      await db.update(
        'sync_queue',
        {
          'status': 'FAILED',
          'error_message': e.toString(),
        },
        where: 'id = ?',
        whereArgs: [queueId],
      );
      rethrow;
    }
  }
}

import '../../domain/entities/service_order.dart';
import '../../domain/repositories/service_order_repository.dart';
import '../datasources/service_order_local_datasource.dart';
import '../datasources/service_order_remote_datasource.dart';
import '../models/service_order_model.dart';
import '../../../../core/network/sync_queue_service.dart';

class ServiceOrderRepositoryImpl implements ServiceOrderRepository {
  final ServiceOrderLocalDataSource _localDataSource;
  final ServiceOrderRemoteDataSource _remoteDataSource;

  ServiceOrderRepositoryImpl(this._localDataSource, this._remoteDataSource);

  @override
  Future<void> saveServiceOrderOffline(ServiceOrder os) async {
    final osModel = ServiceOrderModel.fromEntity(os.copyWith(
      syncStatus: 'pending',
    ));

    // 1. Persistir localmente
    await _localDataSource.insertServiceOrder(osModel);

    // 2. Enfileirar na fila de sincronização
    await SyncQueueService.instance.queueItem(
      itemType: 'service_order',
      itemId: os.id,
      operation: 'CREATE',
      payload: osModel.toJson(),
    );

    // 3. Sincronizar imediatamente em background
    SyncQueueService.instance.processQueue();

    print('[ServiceOrderRepository] OS offline salva e enfileirada: ${os.id}');
  }

  @override
  Future<List<ServiceOrder>> listLocalServiceOrders({String? status, String? plate}) async {
    return await _localDataSource.listServiceOrders(status: status, plate: plate);
  }

  @override
  Future<ServiceOrder?> getLocalServiceOrderById(String id) async {
    return await _localDataSource.getServiceOrderById(id);
  }

  @override
  Future<void> syncServiceOrders() async {
    try {
      print('[ServiceOrderRepository] Buscando OSs remotas...');
      final remoteOrders = await _remoteDataSource.getServiceOrders();
      if (remoteOrders.isNotEmpty) {
        await _localDataSource.insertBatch(remoteOrders);
        print('[ServiceOrderRepository] ${remoteOrders.length} OSs sincronizadas localmente.');
      }
    } catch (e) {
      print('[ServiceOrderRepository] Falha ao baixar OSs: $e');
    }
  }

  @override
  Future<void> updateStatus(String id, String status) async {
    // 1. Atualizar localmente
    await _localDataSource.updateServiceOrderStatus(id, status, syncStatus: 'pending');

    // 2. Adicionar à fila de sincronização
    await SyncQueueService.instance.queueItem(
      itemType: 'service_order_status',
      itemId: id,
      operation: 'UPDATE',
      payload: {'status': status},
    );

    print('[ServiceOrderRepository] Atualização de status da OS enfileirada: $id -> $status');
  }

  @override
  Future<void> addCustomerSignature(String osId, String signaturePath) async {
    final photo = ServiceOrderPhoto(
      id: 'sig_${DateTime.now().millisecondsSinceEpoch}',
      serviceOrderId: osId,
      photoUrl: signaturePath,
      photoType: 'SIGNATURE',
      createdAt: DateTime.now().toIso8601String(),
    );

    // Persistir foto localmente
    await _localDataSource.insertServiceOrderPhoto(photo);

    // Obter OS atualizada e re-enfileirar
    final updatedOs = await _localDataSource.getServiceOrderById(osId);
    if (updatedOs != null) {
      await SyncQueueService.instance.queueItem(
        itemType: 'service_order',
        itemId: osId,
        operation: 'CREATE',
        payload: updatedOs.toJson(),
      );
      // Sincronizar imediatamente em background
      SyncQueueService.instance.processQueue();
    }
  }
}

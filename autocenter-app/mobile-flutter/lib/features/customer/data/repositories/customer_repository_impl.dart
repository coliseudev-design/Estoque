import '../models/customer_model.dart';
import '../datasources/customer_local_data_source.dart';
import '../datasources/customer_remote_data_source.dart';
import '../../../../core/network/sync_queue_service.dart';

class CustomerRepositoryImpl {
  final CustomerLocalDataSource _localDataSource;
  final CustomerRemoteDataSource _remoteDataSource;

  CustomerRepositoryImpl(this._localDataSource, this._remoteDataSource);

  /// Sincroniza a base de clientes trazendo do Middleware e salvando no SQLite
  Future<void> syncCustomers() async {
    try {
      // 1. Fetch remote 
      print('[CustomerRepository] Iniciando download de clientes...');
      final customers = await _remoteDataSource.getCustomers();
      
      if (customers.isNotEmpty) {
        // 2. Insert into SQLite (Batch UPSERT)
        await _localDataSource.insertBatch(customers);
        print('[CustomerRepository] ${customers.length} clientes sincronizados localmente.');
      }
    } catch (e) {
      print('[CustomerRepository] Falha ao sincronizar clientes: $e');
      // Engole a exception de rede para não quebrar a UI. O App foi feito para ser offline-first.
    }
  }

  /// Busca offline no banco SQL
  Future<List<CustomerModel>> searchLocalCustomers(String query) async {
    // Retorna rapidamente do SQLite
    return await _localDataSource.searchCustomers(query);
  }

  Future<int> getCustomerCount() async {
    return await _localDataSource.getCustomerCount();
  }

  /// Cadastra um cliente offline, salva localmente e coloca na fila de sincronização
  Future<void> saveCustomerOffline(CustomerModel customer) async {
    final localId = 'local_${DateTime.now().millisecondsSinceEpoch}';
    final offlineCustomer = customer.copyWith(
      localId: localId,
      syncStatus: 'pending',
    );
    
    // 1. Salvar no SQLite local
    await _localDataSource.insertCustomer(offlineCustomer);
    
    // 2. Colocar na fila de sincronização
    await SyncQueueService.instance.queueItem(
      itemType: 'customer',
      itemId: localId,
      operation: 'CREATE',
      payload: offlineCustomer.toJson(),
    );
    
    // 3. Sincronizar imediatamente em background
    SyncQueueService.instance.processQueue();
    
    print('[CustomerRepository] Cliente offline cadastrado e enfileirado: $localId');
  }
}

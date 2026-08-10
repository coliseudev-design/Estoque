import 'dart:io';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:workmanager/workmanager.dart';
import '../database/database_helper.dart';
import 'api_client.dart';
import 'sync_queue_service.dart';
import '../../features/customer/data/datasources/customer_local_data_source.dart';
import '../../features/customer/data/datasources/customer_remote_data_source.dart';
import '../../features/customer/data/repositories/customer_repository_impl.dart';
import '../../features/services/data/datasources/catalog_local_datasource.dart';
import '../../features/services/data/datasources/catalog_remote_datasource.dart';
import '../../features/services/data/repositories/catalog_repository_impl.dart';
import '../../features/draft/data/datasources/draft_local_datasource.dart';
import '../../features/draft/data/datasources/draft_remote_datasource.dart';

const String syncDraftsTask = "syncDraftsTask";
const String syncCustomersTask = "syncCustomersTask";
const String syncCatalogTask = "syncCatalogTask";

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      if (task == syncDraftsTask) {
        print("Iniciando Sync de Fila de Sincronia Offline...");
        await SyncQueueService.instance.processQueue();
        return Future.value(true);
      }
      
      if (task == syncCustomersTask) {
        print("Iniciando Sync de Clientes Offline...");
        final local = CustomerLocalDataSource();
        final remote = CustomerRemoteDataSource();
        final repo = CustomerRepositoryImpl(local, remote);
        
        await repo.syncCustomers();
        return Future.value(true);
      }

      if (task == syncCatalogTask) {
        print("Iniciando Sync de Catálogo (Produtos/Serviços) Offline...");
        final local = CatalogLocalDataSource();
        final remote = CatalogRemoteDataSource();
        final repo = CatalogRepositoryImpl(local, remote);
        
        await repo.syncCatalog();
        return Future.value(true);
      }

      return Future.value(false);
    } catch (e) {
      print("Erro no Background Job: $e");
      return Future.value(false); // Retornar false fará o OS reagendar graças ao backOffPolicy
    }
  });
}

class SyncService {
  static Future<void> initialize() async {
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: true, // Ideal tirar para Release
    );
  }

  /// Registra a fila para enviar ao plugar no Wi-Fi
  static void registerOfflineSync() {
    Workmanager().registerOneOffTask(
      "sync-drafts-\${DateTime.now().millisecondsSinceEpoch}", 
      syncDraftsTask,
      constraints: Constraints(
        networkType: NetworkType.connected, // Economiza 4G se o OS achar necessário
      ),
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(minutes: 5),
    );
  }

  /// Registra a fila de download da base de clientes (Offline-first)
  static void registerCustomerSync() {
    Workmanager().registerOneOffTask(
      "sync-customers-\${DateTime.now().millisecondsSinceEpoch}", 
      syncCustomersTask,
      constraints: Constraints(
        networkType: NetworkType.connected, 
      ),
    );
  }

  /// Registra a fila de download da base de catálogo (Offline-first)
  static void registerCatalogSync() {
    Workmanager().registerOneOffTask(
      "sync-catalog-\${DateTime.now().millisecondsSinceEpoch}", 
      syncCatalogTask,
      constraints: Constraints(
        networkType: NetworkType.connected, 
      ),
    );
  }
}

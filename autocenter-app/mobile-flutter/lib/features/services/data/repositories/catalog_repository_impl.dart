import '../datasources/catalog_remote_datasource.dart';
import '../datasources/catalog_local_datasource.dart';
import '../models/catalog_item_model.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class CatalogRepositoryImpl {
  final CatalogLocalDataSource localDataSource;
  final CatalogRemoteDataSource remoteDataSource;

  CatalogRepositoryImpl(this.localDataSource, this.remoteDataSource);

  Future<void> syncCatalog() async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        throw Exception('Sem conexão com a internet');
      }

      print("[CatalogRepository] Baixando Catálogo do Middleware...");
      final remoteItems = await remoteDataSource.pullCatalog();
      
      if (remoteItems.isNotEmpty) {
        print("[CatalogRepository] Sucesso! Salvando ${remoteItems.length} itens no SQFlite...");
        await localDataSource.replaceCatalogBatch(remoteItems);
      }

      print("[CatalogRepository] Baixando Espécies de Pagamento...");
      final remoteSpecies = await remoteDataSource.pullPaymentSpecies();
      if (remoteSpecies.isNotEmpty) {
        print("[CatalogRepository] Salvando ${remoteSpecies.length} espécies no SQFlite...");
        await localDataSource.replacePaymentSpeciesBatch(remoteSpecies);
      }

      print("[CatalogRepository] Baixando Condições de Pagamento...");
      final remoteConditions = await remoteDataSource.pullPaymentConditions();
      if (remoteConditions.isNotEmpty) {
        print("[CatalogRepository] Salvando ${remoteConditions.length} condições no SQFlite...");
        await localDataSource.replacePaymentConditionsBatch(remoteConditions);
      }

      print("[CatalogRepository] Baixando Naturezas de Operação...");
      final remoteNaturezas = await remoteDataSource.pullNaturezas();
      if (remoteNaturezas.isNotEmpty) {
        print("[CatalogRepository] Salvando ${remoteNaturezas.length} naturezas no SQFlite...");
        await localDataSource.replaceNaturezasBatch(remoteNaturezas);
      }
    } catch (e) {
      print("[CatalogRepository] Erro no sync: $e");
      rethrow;
    }
  }

  Future<List<String>> getCategories() async {
    return await localDataSource.getCategories();
  }

  Future<List<CatalogItemModel>> getCatalogByCategory(String category) async {
    return await localDataSource.getCatalogByCategory(category);
  }

  Future<List<CatalogItemModel>> getAllCatalog() async {
    return await localDataSource.getAllCatalog();
  }

  Future<int> getCatalogCount() async {
    return await localDataSource.getCatalogCount();
  }
}

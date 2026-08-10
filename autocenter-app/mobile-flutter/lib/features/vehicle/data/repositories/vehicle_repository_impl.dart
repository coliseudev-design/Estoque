import '../../domain/entities/vehicle.dart';
import '../../domain/repositories/vehicle_repository.dart';
import '../datasources/vehicle_local_datasource.dart';
import '../datasources/vehicle_remote_datasource.dart';

class VehicleRepositoryImpl implements VehicleRepository {
  final VehicleLocalDataSource localDataSource;
  final VehicleRemoteDataSource remoteDataSource;

  VehicleRepositoryImpl({
    required this.localDataSource,
    required this.remoteDataSource,
  });

  @override
  Future<Vehicle> getVehicleByPlate(String plate) async {
    // Estratégia: sempre busca da API primeiro (dados sempre frescos).
    // Só usa cache local se a API falhar (sem conexão).
    try {
      final remoteVehicle = await remoteDataSource.getVehicleByPlate(plate);
      
      // Grava (ou sobrescreve) o cache local com os dados frescos
      await localDataSource.cacheVehicle(remoteVehicle);
      
      return remoteVehicle;
    } catch (_) {
      // Fallback: tenta o cache local (offline)
      final localVehicle = await localDataSource.getVehicleByPlate(plate);
      if (localVehicle != null) {
        return localVehicle;
      }
      // Repropaga o erro original se não houver cache
      rethrow;
    }
  }

  @override
  Future<List<Vehicle>> getVehiclesByCustomerId(int customerId) async {
    try {
      final remoteVehicles = await remoteDataSource.getVehiclesByCustomerId(customerId);
      if (remoteVehicles.isNotEmpty) {
        await localDataSource.cacheVehicles(remoteVehicles);
      }
      return remoteVehicles;
    } catch (_) {
      return await localDataSource.getVehiclesByCustomerId(customerId);
    }
  }
}

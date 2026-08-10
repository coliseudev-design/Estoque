import '../entities/vehicle.dart';

abstract class VehicleRepository {
  /// Fetches a vehicle by plate.
  /// Throws [ServerException] if 5xx or offline fails.
  /// Throws [QuotaException] if 429 to trigger manual fallback.
  Future<Vehicle> getVehicleByPlate(String plate);
  Future<List<Vehicle>> getVehiclesByCustomerId(int customerId);
}

class QuotaException implements Exception {
  final String message;
  QuotaException(this.message);
}

class ServerException implements Exception {
  final String message;
  ServerException(this.message);
}

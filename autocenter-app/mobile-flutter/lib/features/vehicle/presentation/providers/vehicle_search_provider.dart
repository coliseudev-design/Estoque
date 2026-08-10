import 'package:flutter/material.dart';
import '../../domain/entities/vehicle.dart';
import '../../domain/repositories/vehicle_repository.dart';

enum VehicleSearchStatus { initial, loading, success, manualFallback, error }

class VehicleSearchProvider extends ChangeNotifier {
  final VehicleRepository repository;

  VehicleSearchProvider({required this.repository});

  VehicleSearchStatus _status = VehicleSearchStatus.initial;
  VehicleSearchStatus get status => _status;

  Vehicle? _vehicle;
  Vehicle? get vehicle => _vehicle;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  Future<void> searchPlate(String plate) async {
    _status = VehicleSearchStatus.loading;
    _vehicle = null; // limpa veículo anterior imediatamente
    _errorMessage = null;
    notifyListeners();

    try {
      _vehicle = await repository.getVehicleByPlate(plate);
      _status = VehicleSearchStatus.success;
    } on QuotaException catch (e) {
      _status = VehicleSearchStatus.manualFallback;
      _errorMessage = e.message;
    } on ServerException catch (e) {
      _status = VehicleSearchStatus.manualFallback;
      _errorMessage = '${e.message}. Preenchimento manual liberado.';
    } catch (e, stack) {
      // ignore: avoid_print
      print('[VehicleSearchProvider] Unexpected error: $e\n$stack');
      _status = VehicleSearchStatus.manualFallback;
      _errorMessage = 'Falha de conexão. Preenchimento manual liberado.';
    }
    notifyListeners();
  }

  void saveManualVehicle(Vehicle manualVehicle) {
    _vehicle = manualVehicle;
    _status = VehicleSearchStatus.success; // Treat manual as success so we can proceed
    notifyListeners();
  }

  void reset() {
    _status = VehicleSearchStatus.initial;
    _vehicle = null;
    _errorMessage = null;
    notifyListeners();
  }
}

import 'package:dio/dio.dart';
import 'dart:convert';
import '../../../../core/network/api_client.dart';
import '../../domain/entities/vehicle.dart';
import '../../domain/repositories/vehicle_repository.dart';

abstract class VehicleRemoteDataSource {
  Future<Vehicle> getVehicleByPlate(String plate);
  Future<List<Vehicle>> getVehiclesByCustomerId(int customerId);
}

const String kApiBrasilToken =
    "eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJodHRwczovL2dhdGV3YXkuYXBpYnJhc2lsLmlvL2FwaS92Mi9hdXRoL2tleWNsb2FrL2V4Y2xhbmdlIiwiaWF0IjoxNzc2Mzc0OTAxLCJleHAiOjE4MDc5MTA5MDEsIm5iZiI6MTc3NjM3NDkwMSwianRpIjoiT1Nxb0NtTk16TjVHaXNwYyIsInN1YiI6IjQxMTg1In0.1ejqxDV-BZfAvP_YZqyTat5HvhaJEHywQ08Pjgawl6c";

class VehicleRemoteDataSourceImpl implements VehicleRemoteDataSource {
  final ApiClient apiClient;

  VehicleRemoteDataSourceImpl({required this.apiClient});

  @override
  Future<Vehicle> getVehicleByPlate(String plate) async {
    final dio = apiClient.instance;
    final cleanPlate = plate.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
    
    try {
      final response = await dio.get('vehicles/$cleanPlate');
      
      final statusCode = response.statusCode ?? 0;
      final body = response.data;

      if (statusCode == 200) {
        return Vehicle.fromJson(body);
      } else {
        throw ServerException('Erro inesperado do Middleware: $statusCode');
      }
    } on DioException catch (e) {
      final status = e.response?.statusCode ?? 0;
      final responseData = e.response?.data;
      
      // Mapeamento de erros estruturados da VPS
      String errorMessage = 'Falha ao consultar parceiro de dados veiculares';
      String code = '';
      
      if (responseData is Map) {
        errorMessage = responseData['message'] ?? responseData['error'] ?? errorMessage;
        code = responseData['code'] ?? '';
      }

      if (status == 404 || code == 'NOT_FOUND') {
        throw ServerException('Veículo não encontrado');
      }
      
      if (status == 429 || code == 'TOO_MANY_REQUESTS' || 
          errorMessage.toLowerCase().contains('cota') || 
          errorMessage.toLowerCase().contains('limit')) {
        throw QuotaException('Limite de cota excedido. Preenchimento manual liberado.');
      }
      
      throw ServerException(errorMessage);
    } catch (e) {
      throw ServerException('Falha de conexão com o Middleware: ${e.toString()}');
    }
  }

  @override
  Future<List<Vehicle>> getVehiclesByCustomerId(int customerId) async {
    final dio = apiClient.instance;
    try {
      final response = await dio.get('vehicles/customer/$customerId');
      if (response.statusCode == 200) {
        final List<dynamic> list = response.data ?? [];
        return list.map((json) => Vehicle.fromJson(json as Map<String, dynamic>)).toList();
      }
      return [];
    } on DioException catch (e) {
      throw ServerException(e.response?.data?['message'] ?? 'Erro ao buscar veículos do cliente no Middleware.');
    } catch (e) {
      throw ServerException('Falha de conexão com o Middleware: ${e.toString()}');
    }
  }
}

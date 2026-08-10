import 'package:dio/dio.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/di/injection.dart';
import '../models/service_order_model.dart';

class ServiceOrderRemoteDataSource {
  final Dio _dio;

  ServiceOrderRemoteDataSource({Dio? dio})
      : _dio = dio ?? (getIt.isRegistered<ApiClient>() ? getIt<ApiClient>().instance : ApiClient().instance);

  Future<ServiceOrderModel?> createServiceOrder(ServiceOrderModel os) async {
    try {
      final response = await _dio.post(
        'service-orders',
        data: os.toJson(),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return ServiceOrderModel.fromJson(response.data);
      }
      return null;
    } on DioException catch (e) {
      String errMsg = 'Falha ao enviar Ordem de Serviço ao Middleware.';
      if (e.response != null && e.response!.data != null) {
        final data = e.response!.data;
        if (data is Map) {
          errMsg = data['error'] ?? data['message'] ?? errMsg;
        } else {
          errMsg = data.toString();
        }
      } else {
        errMsg = '${e.message}';
      }
      throw Exception(errMsg);
    } catch (e) {
      throw Exception('Erro inesperado ao criar OS remotamente: $e');
    }
  }

  Future<List<ServiceOrderModel>> getServiceOrders({
    String? status,
    String? plate,
    int page = 1,
    int limit = 50,
  }) async {
    try {
      final Map<String, dynamic> queryParams = {
        'page': page,
        'limit': limit,
      };
      if (status != null && status.isNotEmpty) {
        queryParams['status'] = status;
      }
      if (plate != null && plate.isNotEmpty) {
        queryParams['plate'] = plate;
      }

      final response = await _dio.get(
        'service-orders',
        queryParameters: queryParams,
      );

      if (response.statusCode == 200) {
        final List<dynamic> list = response.data['serviceOrders'] ?? [];
        return list.map((json) => ServiceOrderModel.fromJson(json)).toList();
      }
      return [];
    } on DioException catch (e) {
      print('DioException [ServiceOrderRemote.getServiceOrders]: ${e.message}');
      throw Exception('Falha ao listar Ordens de Serviço.');
    } catch (e) {
      throw Exception('Erro ao buscar OS remota: $e');
    }
  }

  Future<ServiceOrderModel?> getServiceOrderDetails(String id) async {
    try {
      final response = await _dio.get('service-orders/$id');
      if (response.statusCode == 200) {
        return ServiceOrderModel.fromJson(response.data);
      }
      return null;
    } on DioException catch (e) {
      print('DioException [ServiceOrderRemote.getServiceOrderDetails]: ${e.message}');
      throw Exception('Falha ao obter detalhes da Ordem de Serviço.');
    } catch (e) {
      throw Exception('Erro ao obter detalhes da OS: $e');
    }
  }

  Future<bool> updateStatus(String id, String status) async {
    try {
      final response = await _dio.patch(
        'service-orders/$id/status',
        data: {'status': status},
      );
      return response.statusCode == 200;
    } on DioException catch (e) {
      print('DioException [ServiceOrderRemote.updateStatus]: ${e.message}');
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> uploadPhotos(String id, List<String> photoPaths) async {
    if (photoPaths.isEmpty) return true;
    try {
      var formData = FormData.fromMap({});
      for (var path in photoPaths) {
        formData.files.add(MapEntry(
          'files[]',
          await MultipartFile.fromFile(path),
        ));
      }

      final response = await _dio.post(
        'service-orders/$id/photos',
        data: formData,
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      print('DioException [ServiceOrderRemote.uploadPhotos]: $e');
      return false;
    }
  }
}

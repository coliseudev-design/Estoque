import 'package:dio/dio.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/di/injection.dart';
import '../models/customer_model.dart';

class CustomerRemoteDataSource {
  final Dio _dio;

  CustomerRemoteDataSource({Dio? dio})
      : _dio = dio ?? (getIt.isRegistered<ApiClient>() ? getIt<ApiClient>().instance : ApiClient().instance);

  Future<List<CustomerModel>> getCustomers({String search = '', int limit = 1000000}) async {
    try {
      final response = await _dio.get(
        'customers', 
        queryParameters: {
          'search': search,
          'limit': limit,
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        return data.map((json) => CustomerModel.fromJson(json)).toList();
      } else {
        throw Exception('Erro ao buscar clientes: ${response.statusCode}');
      }
    } on DioException catch (e) {
      String errMsg = 'Falha de conexão com Middleware.';
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
      throw Exception('Erro inesperado: $e');
    }
  }

  Future<CustomerModel> createCustomer(CustomerModel customer) async {
    try {
      final response = await _dio.post(
        'customers',
        data: customer.toJson(),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return CustomerModel.fromJson(response.data);
      } else {
        throw Exception('Erro ao cadastrar cliente remotamente: ${response.statusCode}');
      }
    } on DioException catch (e) {
      String errMsg = 'Falha de conexão com Middleware ao cadastrar cliente.';
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
      throw Exception('Erro inesperado ao cadastrar cliente: $e');
    }
  }
}

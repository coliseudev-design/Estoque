import 'package:dio/dio.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/di/injection.dart';
import '../models/seller_model.dart';

class SellersRemoteDataSource {
  final Dio _dio;

  SellersRemoteDataSource({Dio? dio})
      : _dio = dio ?? (getIt.isRegistered<ApiClient>() ? getIt<ApiClient>().instance : ApiClient().instance);

  Future<List<SellerModel>> getSellers() async {
    try {
      final response = await _dio.get('sellers');

      if (response.statusCode == 200) {
        final List<dynamic> data = response.data['sellers'] ?? [];
        return data.map((json) => SellerModel.fromMap(json)).toList();
      } else {
        throw Exception('Erro ao buscar vendedores: ${response.statusCode}');
      }
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final dataErr = e.response?.data?['error'] ?? e.response?.data?['message'] ?? e.message;
      print('DioException [SellersRemote]: $dataErr');
      throw Exception('Conexão falhou ($status): $dataErr');
    } catch (e) {
      print('Erro geral [SellersRemote]: $e');
      throw Exception('Falha no processamento: $e');
    }
  }
}

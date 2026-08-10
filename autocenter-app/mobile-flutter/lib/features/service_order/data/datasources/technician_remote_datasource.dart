import 'package:dio/dio.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/di/injection.dart';
import '../models/technician_model.dart';

class TechnicianRemoteDataSource {
  final Dio _dio;

  TechnicianRemoteDataSource({Dio? dio})
      : _dio = dio ?? (getIt.isRegistered<ApiClient>() ? getIt<ApiClient>().instance : ApiClient().instance);

  Future<List<TechnicianModel>> getTechnicians() async {
    try {
      final response = await _dio.get('technicians');
      if (response.statusCode == 200) {
        final List<dynamic> list = response.data is List ? response.data : (response.data['technicians'] ?? []);
        return list.map((json) => TechnicianModel.fromJson(json as Map<String, dynamic>)).toList();
      }
      return [];
    } on DioException catch (e) {
      print('DioException [TechnicianRemoteDataSource.getTechnicians]: ${e.message}');
      return [];
    } catch (e) {
      print('Exception [TechnicianRemoteDataSource.getTechnicians]: $e');
      return [];
    }
  }
}

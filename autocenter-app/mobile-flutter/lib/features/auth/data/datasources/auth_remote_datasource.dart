import '../../../../core/network/api_client.dart';

abstract class AuthRemoteDataSource {
  Future<Map<String, dynamic>> login(String username, String password);
}

class AuthRemoteDataSourceImpl implements AuthRemoteDataSource {
  final ApiClient apiClient;

  AuthRemoteDataSourceImpl({required this.apiClient});

  @override
  Future<Map<String, dynamic>> login(String username, String password) async {
    final response = await apiClient.instance.post(
      '/auth/login',
      data: {
        'username': username, // Identificação do Vendedor no ERP
        'password': password,
      },
    );
    return {
      'token': response.data['access_token'],
      'vendedor_code': username, // Assumindo echo caso precise
    };
  }
}

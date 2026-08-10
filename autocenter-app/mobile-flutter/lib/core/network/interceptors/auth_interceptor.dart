import 'package:dio/dio.dart';
import '../../di/injection.dart';
import '../auth/auth_token_manager.dart';

class AuthInterceptor extends Interceptor {
  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    try {
      final tokenManager = getIt<AuthTokenManager>();
      final token = await tokenManager.getToken();

      if (token != null) {
        options.headers['Authorization'] = 'Bearer $token';
      }

      final branchId = await tokenManager.getBranchId();
      if (branchId != null) {
        options.headers['X-Branch-Id'] = branchId;
      }
    } catch (e) {
      // Ignorar exceções de leitura, seguindo como request anônimo
    }

    super.onRequest(options, handler);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 401) {
      print('[AuthInterceptor] 401 Unauthorized detectado. Tentando renovar o token...');
      final tokenManager = getIt<AuthTokenManager>();
      final success = await tokenManager.refreshTokens();

      if (success) {
        final newToken = await tokenManager.getToken();
        if (newToken != null) {
          print('[AuthInterceptor] Token renovado com sucesso. Re-executando a requisição...');
          try {
            final options = err.requestOptions;
            options.headers['Authorization'] = 'Bearer $newToken';

            // Re-executa a requisição usando um novo Dio para evitar loops e outros interceptors
            final retryDio = Dio(BaseOptions(
              baseUrl: options.baseUrl,
              connectTimeout: options.connectTimeout,
              receiveTimeout: options.receiveTimeout,
            ));

            final response = await retryDio.fetch(options);
            return handler.resolve(response);
          } catch (retryErr) {
            print('[AuthInterceptor] Falha ao re-executar requisição pós-refresh: $retryErr');
          }
        }
      } else {
        print('[AuthInterceptor] Renovação de token falhou. Limpando sessão do vendedor.');
        await tokenManager.clearVendedor();
      }
    }

    super.onError(err, handler);
  }
}

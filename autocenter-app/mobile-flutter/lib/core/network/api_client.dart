import 'package:dio/dio.dart';
import 'interceptors/error_interceptor.dart';
import 'interceptors/auth_interceptor.dart';
import 'package:dio_smart_retry/dio_smart_retry.dart';

class ApiClient {
  late Dio _dio;

  ApiClient() {
    _dio = Dio(
      BaseOptions(
        baseUrl: const String.fromEnvironment('API_URL', defaultValue: 'http://localhost:3000/api'),
        // SPEC-mobile-flutter: timeout explicito de 15s (15000ms) default
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        sendTimeout: const Duration(seconds: 45), // Upload demorado
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    _setupInterceptors();
  }

  void _setupInterceptors() {
    // 0. Autenticação na VPS
    _dio.interceptors.add(AuthInterceptor());

    // 1. Tratamento Global de Erros customizado da Cloud
    _dio.interceptors.add(ErrorInterceptor());

    // 2. Exponential Backoff p/ 503 Service Unavailable e falhas de rede (SPEC-mobile-flutter)
    _dio.interceptors.add(
      RetryInterceptor(
        dio: _dio,
        logPrint: print, // Use logger in production
        retries: 3, 
        retryDelays: const [
          Duration(seconds: 1), 
          Duration(seconds: 3), 
          Duration(seconds: 5),
        ],
        retryEvaluator: (DioException error, int attempt) {
          // Apenas tentar de novo se for 503, Timeout ou erro offline.
          if (error.type == DioExceptionType.connectionTimeout || 
              error.type == DioExceptionType.receiveTimeout ||
              error.type == DioExceptionType.unknown) {
            return true;
          }
          if (error.response?.statusCode == 503) return true;
          if (error.response?.statusCode == 504) return true;
          
          return false; // Erros como 400 ou 413 nao entram em loop
        },
      ),
    );
  }

  Dio get instance => _dio;

  void updateBaseUrl(String newBaseUrl) {
    var url = newBaseUrl;
    if (!url.endsWith('/')) {
      url = '$url/';
    }
    _dio.options.baseUrl = url;
  }

  /// Cria um Dio auxiliar apontando para o Identity Server.
  /// Usado exclusivamente durante a ativação do dispositivo.
  /// NÃO adiciona os interceptors de auth (o Identity não precisa de JWT).
  Dio createIdentityClient(String identityBaseUrl) {
    return Dio(
      BaseOptions(
        baseUrl: identityBaseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    )..interceptors.add(ErrorInterceptor());
  }
}


import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config_service.dart';
import '../session/session_service.dart';

/// Interceptador que anexa o JWT, CompanyId e BranchId nas requisições do Dio.
///
/// Headers enviados em cada request:
/// - Authorization: Bearer <jwt>   — autenticação do vendedor
/// - X-Company-Id: <companyId>    — isolamento multi-tenant no Sales API (Rule-03)
/// - X-Branch-Id:  <branchId>     — isolamento de filial no middleware (FASE 3)
class JwtInterceptor extends Interceptor {
  final SessionService _sessionService;

  JwtInterceptor(this._sessionService);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    // Busca o token do device persistentado em AppConfigService
    final config = AppConfigService();
    final String? token = await config.getAccessToken();
    
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }

    // O middleware (Node) exige a API-Key preenchida em todas as chamadas
    final String? activationKey = await config.getActivationKey();
    if (activationKey != null && activationKey.isNotEmpty) {
      options.headers['API-Key'] = activationKey;
    }

    // Envia CompanyId para o TenantMiddleware do Sales API (Rule-03)
    if (_sessionService.isLoggedIn) {
      try {
        final companyId = _sessionService.companyId;
        if (companyId.isNotEmpty) {
          options.headers['X-Company-Id'] = companyId;
        }
      } catch (_) {
        // Sem sessão ativa — não envia o header
      }
    }

    // FASE 3: Envia BranchId selecionado pelo vendedor (Rule-03 multi-tenant)
    final String? branchId = await config.getBranchId();
    if (branchId != null && branchId.isNotEmpty) {
      options.headers['X-Branch-Id'] = branchId;
    }

    debugPrint('[JwtInterceptor] ${options.method} ${options.uri} '
        'hasAuth=${token != null && token.isNotEmpty} '
        'hasApiKey=${activationKey != null && activationKey.isNotEmpty} '
        'branchId=${branchId ?? "none"}');
    
    super.onRequest(options, handler);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    // 401: Token inválido ou expirado
    if (err.response?.statusCode == 401) {
      debugPrint('[JwtInterceptor] 401 Unauthorized detected. Attempting token refresh...');
      
      final success = await _sessionService.refreshTokens();
      
      if (success && _sessionService.accessToken != null) {
        debugPrint('[JwtInterceptor] Token refreshed successfully. Retrying request...');
        try {
          // Cria novo RequestOptions clonando o original
          final options = err.requestOptions;
          options.headers['Authorization'] = 'Bearer ${_sessionService.accessToken}';
          
          // Re-executa a requisição usando um novo Dio para evitar loops de interceptor
          final retryDio = Dio(BaseOptions(
            baseUrl: options.baseUrl,
            connectTimeout: options.connectTimeout,
            receiveTimeout: options.receiveTimeout,
          ));
          
          final newToken = await AppConfigService().getAccessToken();
          options.headers['Authorization'] = 'Bearer $newToken';
          
          final response = await retryDio.fetch(options);
          return handler.resolve(response);
        } catch (retryErr) {
          debugPrint('[JwtInterceptor] Retry failed: $retryErr');
        }
      } else {
         debugPrint('[JwtInterceptor] Token refresh failed. Forcing logout.');
         await _sessionService.logout();
      }
    }
    
    super.onError(err, handler);
  }
}

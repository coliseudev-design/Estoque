/// Cliente HTTP da API do Coliseu Estoque e do Coliseu.Identity.
library;

import 'package:dio/dio.dart';

import '../config/app_config.dart';

class ApiException implements Exception {
  final String message;
  final String? code;
  final int? status;
  final Map<String, dynamic>? data;
  const ApiException(this.message, {this.code, this.status, this.data});

  /// Falha de rede (sem resposta do servidor) — a leitura fica na fila offline.
  bool get isNetwork => status == null;
  bool get isAuth => status == 401;

  @override
  String toString() => message;

  static ApiException from(Object e) {
    if (e is ApiException) return e;
    if (e is DioException) {
      final res = e.response;
      if (res == null) {
        return const ApiException('Sem conexão com o servidor. As leituras ficam salvas no aparelho.');
      }
      final body = res.data is Map<String, dynamic> ? res.data as Map<String, dynamic> : <String, dynamic>{};
      return ApiException(
        (body['error'] ?? 'Erro ${res.statusCode}').toString(),
        code: body['code'] as String?,
        status: res.statusCode,
        data: body,
      );
    }
    return ApiException(e.toString());
  }
}

class ApiClient {
  ApiClient(this._config) {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 25),
      sendTimeout: const Duration(seconds: 25),
      contentType: Headers.jsonContentType,
    ));
    _dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      final token = _config.sessionToken;
      if (token.isNotEmpty && options.headers['Authorization'] == null && options.extra['noAuth'] != true) {
        options.headers['Authorization'] = 'Bearer $token';
      }
      handler.next(options);
    }));
  }

  final AppConfig _config;
  late final Dio _dio;

  /// Chamado quando a API recusa o token (sessão expirada ou usuário desativado).
  void Function()? onUnauthorized;

  String get _base => _config.apiUrl;

  /// Executa a chamada; respostas sem corpo (204) viram null.
  Future<Map<String, dynamic>?> _run(Future<Response> Function() call) async {
    try {
      final data = (await call()).data;
      return data is Map<String, dynamic> ? data : null;
    } catch (e) {
      final ex = ApiException.from(e);
      if (ex.isAuth) onUnauthorized?.call();
      throw ex;
    }
  }

  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? query}) async =>
      await _run(() => _dio.get('$_base$path', queryParameters: query)) ?? const {};

  Future<Map<String, dynamic>?> post(String path, [Object? body]) =>
      _run(() => _dio.post('$_base$path', data: body ?? const {}));

  // ── Coliseu.Identity (ativação do aparelho) ──────────────────────────────

  Future<Map<String, dynamic>> identityDeviceLogin(String identityUrl, Map<String, dynamic> body) async {
    try {
      final res = await _dio.post('$identityUrl/auth/device-login', data: body, options: Options(extra: {'noAuth': true}));
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<Map<String, dynamic>> identityRefresh(String identityUrl, String refreshToken) async {
    try {
      final res = await _dio.post('$identityUrl/auth/refresh',
          data: {'refreshToken': refreshToken}, options: Options(extra: {'noAuth': true}));
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  // ── Pareamento pelo painel do Estoque ────────────────────────────────────

  /// Testa se o endereço responde e é uma API do Coliseu Estoque.
  Future<void> health(String apiUrl) async {
    try {
      final res = await _dio.get('$apiUrl/health',
          options: Options(extra: {'noAuth': true}, receiveTimeout: const Duration(seconds: 8)));
      final body = res.data;
      if (body is! Map || body['status'] == null) {
        throw const ApiException('Esse endereço respondeu, mas não é a API do Coliseu Estoque.');
      }
    } catch (e) {
      if (e is ApiException) rethrow;
      final ex = ApiException.from(e);
      throw ex.isNetwork
          ? ApiException('Não consegui falar com $apiUrl. Confira o endereço e se o celular está na mesma rede/internet.')
          : ex;
    }
  }

  /// Troca o código de uso único do painel pela credencial do aparelho.
  Future<Map<String, dynamic>> pair(String apiUrl, Map<String, dynamic> body) async {
    try {
      final res = await _dio.post('$apiUrl/v1/auth/pair', data: body, options: Options(extra: {'noAuth': true}));
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  /// Login do operador em aparelho pareado: credencial do aparelho + usuário + PIN.
  Future<Map<String, dynamic>> appLogin(String deviceKey, String login, String pin, String appVersion) async {
    try {
      final res = await _dio.post('$_base/v1/auth/app-login',
          data: {'login': login, 'pin': pin, 'appVersion': appVersion},
          options: Options(headers: {'X-Device-Key': deviceKey}, extra: {'noAuth': true}));
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  /// Login do operador: JWT do aparelho (Identity) + usuário + PIN.
  Future<Map<String, dynamic>> operatorLogin(String deviceToken, String login, String pin) async {
    try {
      final res = await _dio.post('$_base/v1/auth/device-login',
          data: {'login': login, 'pin': pin},
          options: Options(headers: {'X-Device-Token': deviceToken}, extra: {'noAuth': true}));
      return res.data as Map<String, dynamic>;
    } catch (e) {
      throw ApiException.from(e);
    }
  }
}

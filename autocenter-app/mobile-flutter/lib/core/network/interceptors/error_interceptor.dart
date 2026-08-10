import 'package:dio/dio.dart';

class ErrorInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    String parsedMessage = _parseVpsErrorToMessage(err);
    String code = err.response?.data?['code'] ?? 'ERR-UNK';

    // Cria excecao enriquecida (Pode ser tratada na camada de Presentation/Bloc)
    final enrichedError = DioException(
      requestOptions: err.requestOptions,
      response: err.response,
      type: err.type,
      error: '[$code] $parsedMessage',
      message: parsedMessage,
    );

    // Repassa pra frente o erro ja traduzido para padrao humano/app
    super.onError(enrichedError, handler);
  }

  String _parseVpsErrorToMessage(DioException err) {
    // Erros sem resposta (Timeout, sem rede, dns)
    if (err.type == DioExceptionType.connectionTimeout) return 'Tempo de conexão esgotado.';
    if (err.type == DioExceptionType.receiveTimeout) return 'O Servidor demorou demais para responder.';
    if (err.response == null) return 'Sem conexão com a rede ou servidor offline.';

    final payload = err.response?.data;
    
    // Tratamento direto do Schema do nosso Middleware VPS
    if (payload != null && payload is Map<String, dynamic>) {
      // Formato padrão aderente à SPEC (VAL-001, etc)
      if (payload.containsKey('message')) {
        return payload['message'];
      }
    }

    // Default fallbacks HTTP
    final status = err.response?.statusCode;
    if (status == 413) return 'As fotos enviadas superam o limite suportado na versão atual da rede.';
    if (status == 404) return 'Recurso não encontrado na Nuvem.';
    if (status == 401) return 'Sua sessão expirou, faça login novamente.';
    if (status == 409) return 'Este orçamento já está em conflito e não pode ser salvo.';
    if (status == 500) return 'Falha interna na Nuvem Auto Center.';

    return 'Ocorreu um erro desconhecido no sincronismo.';
  }
}

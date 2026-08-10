import '../../../../core/network/api_client.dart';

/// Resultado da ativação de dispositivo no Identity Server.
class ActivationResult {
  final String accessToken;
  final String refreshToken;
  final int expiresInSeconds;
  final String baseUrl;
  final String companyName;
  final String tenantId;
  final String deviceId;

  const ActivationResult({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresInSeconds,
    required this.baseUrl,
    required this.companyName,
    required this.tenantId,
    required this.deviceId,
  });

  factory ActivationResult.fromJson(Map<String, dynamic> json) {
    return ActivationResult(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String,
      expiresInSeconds: json['expiresInSeconds'] as int,
      baseUrl: json['baseUrl'] as String,
      companyName: json['companyName'] as String,
      tenantId: json['tenantId'] as String,
      deviceId: json['deviceId'] as String,
    );
  }
}

abstract class ActivationRemoteDataSource {
  /// Ativa este dispositivo no Coliseu Identity Server usando a ActivationKey.
  ///
  /// [identityBaseUrl] — URL do Identity Server (ex: "https://identity.coliseusistemas.com.br")
  /// [activationKey]   — Chave de 10 caracteres gerada no Admin Panel
  /// [deviceUuid]      — UUID único do hardware (Android ID)
  /// [model]           — Modelo do dispositivo (ex: "Samsung Galaxy A53")
  /// [os]              — Versão do SO (ex: "Android 13")
  /// [appVersion]      — Versão do AutoCenter App (ex: "1.0.0")
  Future<ActivationResult> activateDevice({
    required String identityBaseUrl,
    required String activationKey,
    required String deviceUuid,
    String? model,
    String? os,
    String? appVersion,
  });
}

class ActivationRemoteDataSourceImpl implements ActivationRemoteDataSource {
  final ApiClient apiClient;

  ActivationRemoteDataSourceImpl({required this.apiClient});

  @override
  Future<ActivationResult> activateDevice({
    required String identityBaseUrl,
    required String activationKey,
    required String deviceUuid,
    String? model,
    String? os,
    String? appVersion,
  }) async {
    // Usa o HttpClient base mas aponta para o Identity Server (URL diferente do middleware)
    // A base URL do Identity é hardcoded na configuração do app — não é o mesmo que o middleware.
    final identityClient = apiClient.createIdentityClient(identityBaseUrl);

    final response = await identityClient.post(
      '/auth/device-login',
      data: {
        'activationKey': activationKey,
        'deviceUuid': deviceUuid,
        'model': model,
        'os': os,
        'appVersion': appVersion,
        'moduleSlug': 'autocenter', // Este app é sempre o módulo autocenter
      },
    );

    return ActivationResult.fromJson(response.data as Map<String, dynamic>);
  }
}

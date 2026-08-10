import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dio/dio.dart';

/// Gerencia os tokens e dados de sessão do AutoCenter App.
///
/// Armazena de forma segura:
/// - JWT de acesso
/// - Refresh Token
/// - Base URL do Middleware AutoCenter (retornada pelo Identity Server na ativação)
/// - Nome e ID da empresa (tenant)
/// - UUID do dispositivo
class AuthTokenManager {
  final FlutterSecureStorage _secureStorage;

  AuthTokenManager({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  // ── Keys ─────────────────────────────────────────────────────────────────
  static const String _accessTokenKey   = 'access_token';
  static const String _refreshTokenKey  = 'refresh_token';
  static const String _baseUrlKey       = 'middleware_base_url';
  static const String _companyNameKey   = 'company_name';
  static const String _tenantIdKey      = 'tenant_id';
  static const String _deviceIdKey      = 'device_id';
  static const String _identityUrlKey   = 'identity_base_url';
  static const String _activationKeyKey = 'activation_key';
  static const String _branchIdKey      = 'branch_id';
  static const String _branchNameKey    = 'branch_name';
  static const String _deptoIdKey       = 'depto_id';
  static const String _empresaErpIdKey  = 'empresa_erp_id';
  static const String _vendedorKey      = 'vendedor_code';
  static const String _vendedorNameKey  = 'vendedor_name';

  // Helper method to safely read values and handle Keystore corruption/decryption failures

  Future<String?> _safeRead(String key) async {
    try {
      return await _secureStorage.read(key: key);
    } catch (e, stackTrace) {
      debugPrint('Error reading secure storage key "$key": $e\n$stackTrace');
      try {
        await clearAll();
      } catch (clearError) {
        debugPrint('Error clearing secure storage: $clearError');
      }
      return null;
    }
  }

  // ── Tokens ────────────────────────────────────────────────────────────────

  Future<void> saveToken(String token) async =>
      _secureStorage.write(key: _accessTokenKey, value: token);

  Future<String?> getToken() async =>
      _safeRead(_accessTokenKey);

  Future<void> deleteToken() async =>
      _secureStorage.delete(key: _accessTokenKey);

  Future<bool> hasToken() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  // ── Refresh Token ─────────────────────────────────────────────────────────

  Future<void> saveRefreshToken(String token) async =>
      _secureStorage.write(key: _refreshTokenKey, value: token);

  Future<String?> getRefreshToken() async =>
      _safeRead(_refreshTokenKey);

  // ── Middleware Base URL (AutoCenter API) ──────────────────────────────────

  /// URL do middleware retornada pelo Identity Server após ativação.
  /// Ex: "https://autocenter.coliseusistemas.com.br"
  Future<void> saveBaseUrl(String url) async =>
      _secureStorage.write(key: _baseUrlKey, value: url);

  Future<String?> getBaseUrl() async =>
      _safeRead(_baseUrlKey);

  // ── Identity Server Base URL ──────────────────────────────────────────────

  /// URL do Identity Server configurada pelo usuário na tela de ativação.
  /// Ex: "https://identity.coliseusistemas.com.br"
  Future<void> saveIdentityUrl(String url) async =>
      _secureStorage.write(key: _identityUrlKey, value: url);

  Future<String?> getIdentityUrl() async =>
      _safeRead(_identityUrlKey);

  Future<void> saveActivationKey(String key) async =>
      _secureStorage.write(key: _activationKeyKey, value: key);

  Future<String?> getActivationKey() async =>
      _safeRead(_activationKeyKey);

  // ── Company info ──────────────────────────────────────────────────────────

  Future<void> saveCompanyName(String name) async =>
      _secureStorage.write(key: _companyNameKey, value: name);

  Future<String?> getCompanyName() async =>
      _safeRead(_companyNameKey);

  Future<void> saveTenantId(String id) async =>
      _secureStorage.write(key: _tenantIdKey, value: id);

  Future<String?> getTenantId() async =>
      _safeRead(_tenantIdKey);

  Future<void> saveDeviceId(String id) async =>
      _secureStorage.write(key: _deviceIdKey, value: id);

  Future<String?> getDeviceId() async =>
      _safeRead(_deviceIdKey);

  // ── Vendedor Code & Name ─────────────────────────────────────────────────
  
  Future<void> saveVendedorCode(String code) async =>
      _secureStorage.write(key: _vendedorKey, value: code);

  Future<String?> getVendedorCode() async =>
      _safeRead(_vendedorKey);

  Future<void> deleteVendedorCode() async =>
      _secureStorage.delete(key: _vendedorKey);

  Future<void> saveVendedorName(String name) async =>
      _secureStorage.write(key: _vendedorNameKey, value: name);

  Future<String?> getVendedorName() async =>
      _safeRead(_vendedorNameKey);

  Future<void> deleteVendedorName() async =>
      _secureStorage.delete(key: _vendedorNameKey);

  Future<void> clearVendedor() async {
    await Future.wait([
      deleteVendedorCode(),
      deleteVendedorName(),
    ]);
  }

  // ── Branch Configuration ──────────────────────────────────────────────────

  Future<void> saveBranchId(String id) async =>
      _secureStorage.write(key: _branchIdKey, value: id);

  Future<String?> getBranchId() async =>
      _safeRead(_branchIdKey);

  Future<void> saveBranchName(String name) async =>
      _secureStorage.write(key: _branchNameKey, value: name);

  Future<String?> getBranchName() async =>
      _safeRead(_branchNameKey);

  Future<void> saveDeptoId(int deptoId) async =>
      _secureStorage.write(key: _deptoIdKey, value: deptoId.toString());

  Future<int?> getDeptoId() async {
    final val = await _safeRead(_deptoIdKey);
    return val != null ? int.tryParse(val) : null;
  }

  Future<void> saveEmpresaErpId(int empresaId) async =>
      _secureStorage.write(key: _empresaErpIdKey, value: empresaId.toString());

  Future<int?> getEmpresaErpId() async {
    final val = await _safeRead(_empresaErpIdKey);
    return val != null ? int.tryParse(val) : null;
  }

  Future<void> setBranch({
    required String branchId,
    required String branchName,
    required int deptoId,
    required int empresaId,
  }) async {
    await Future.wait([
      saveBranchId(branchId),
      saveBranchName(branchName),
      saveDeptoId(deptoId),
      saveEmpresaErpId(empresaId),
    ]);
  }

  Future<void> clearBranch() async {
    await Future.wait([
      _secureStorage.delete(key: _branchIdKey),
      _secureStorage.delete(key: _branchNameKey),
      _secureStorage.delete(key: _deptoIdKey),
      _secureStorage.delete(key: _empresaErpIdKey),
    ]);
  }

  Future<bool> hasBranchSelected() async {
    final id = await getBranchId();
    return id != null && id.isNotEmpty;
  }

  // ── Session Management ────────────────────────────────────────────────────

  /// Verifica se o dispositivo está ativado (tem baseUrl configurada).
  Future<bool> isActivated() async {
    final url = await getBaseUrl();
    return url != null && url.isNotEmpty;
  }

  /// Salva todos os dados da sessão após ativação bem-sucedida.
  Future<void> saveSession({
    required String accessToken,
    required String refreshToken,
    required String baseUrl,
    required String companyName,
    required String tenantId,
    required String deviceId,
    required String identityUrl,
  }) async {
    await Future.wait([
      saveToken(accessToken),
      saveRefreshToken(refreshToken),
      saveBaseUrl(baseUrl),
      saveCompanyName(companyName),
      saveTenantId(tenantId),
      saveDeviceId(deviceId),
      saveIdentityUrl(identityUrl),
    ]);
  }

  /// Remove todos os dados de sessão (logout ou reset de ativação).
  Future<void> clearAll() async =>
      _secureStorage.deleteAll();

  /// Tenta renovar o Access Token enviando o Refresh Token para a Identity API.
  Future<bool> refreshTokens() async {
    final refreshToken = await getRefreshToken();
    final identityUrl = await getIdentityUrl();
    
    if (refreshToken == null || refreshToken.isEmpty || identityUrl == null || identityUrl.isEmpty) {
      debugPrint('[AuthTokenManager] Sem refresh token ou URL de identidade cadastrados para renovação.');
      return false;
    }

    try {
      final dio = Dio(BaseOptions(
        baseUrl: identityUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
      ));

      final response = await dio.post('/auth/refresh', data: {
        'refreshToken': refreshToken,
      });

      if (response.statusCode == 200 && response.data != null) {
        final newAccess = response.data['accessToken'] as String?;
        final newRefresh = response.data['refreshToken'] as String?;
        
        if (newAccess != null && newRefresh != null) {
          await saveToken(newAccess);
          await saveRefreshToken(newRefresh);
          debugPrint('[AuthTokenManager] Token JWT renovado com sucesso.');
          return true;
        }
      }
      return false;
    } catch (e) {
      debugPrint('[AuthTokenManager] Falha ao renovar tokens: $e');
      return false;
    }
  }
}

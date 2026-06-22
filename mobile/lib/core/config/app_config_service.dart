/// AppConfigService — Persiste configurações globais do aplicativo.
///
/// Responsabilidades:
/// - Salvar e carregar a URL do servidor middle (SharedPreferences)
/// - Prover valor padrão quando nenhuma URL foi configurada
///
/// Rule-04 (Secrets): a API Key segue o mesmo padrão e é armazenada
/// de forma isolada, nunca logada.
library;

import 'package:shared_preferences/shared_preferences.dart';

/// Configurações persistidas localmente no dispositivo.
class AppConfigService {
  static const String _keyServerUrl      = 'config_server_url';
  static const String _keyApiKey         = 'config_api_key';
  static const String _keyIdentityUrl    = 'config_identity_url';

  static const String _keyAccessToken    = 'config_access_token';
  static const String _keyRefreshToken   = 'config_refresh_token';
  static const String _keyTenantId       = 'config_tenant_id';
  static const String _keyCompanyName    = 'config_company_name';
  static const String _keyActivationKey  = 'config_activation_key';

  // Branch (filial) selecionada pelo vendedor após o login
  static const String _keyBranchId       = 'config_branch_id';
  static const String _keyBranchName     = 'config_branch_name';
  static const String _keyBranchErpDeptoPadrao = 'config_branch_erp_depto_padrao';
  static const String _keyBranchErpEmpresaId   = 'config_branch_erp_empresa_id';

  // ─────────────────────────────────────────────────────────────────────────
  // Valores padrão
  // ─────────────────────────────────────────────────────────────────────────

  /// URL do servidor (middleware Node.js — porta 3000).
  static const String defaultServerUrl = 'https://licencas.coliseusistemas.com.br';

  /// URL do servidor de identidade (Coliseu.Identity).
  static const String defaultIdentityUrl = 'https://adminlicencas.coliseusistemas.com.br';

  /// API Key padrão para dev local — deve coincidir com API_KEY no .env do middleware.
  static const String defaultApiKey = 'Col@13894645';

  // ─────────────────────────────────────────────────────────────────────────
  // Leitura
  // ─────────────────────────────────────────────────────────────────────────

  /// Retorna a URL do servidor configurada (ou o valor padrão).
  Future<String> getServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyServerUrl) ?? defaultServerUrl;
  }

  /// Retorna a API Key configurada (ou o valor padrão).
  Future<String> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyApiKey) ?? defaultApiKey;
  }

  /// Retorna a URL do Identity Server configurada.
  Future<String> getIdentityUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyIdentityUrl) ?? defaultIdentityUrl;
  }

  /// Retorna a chave de ativação salva (ou null se não ativado ainda).
  Future<String?> getActivationKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyActivationKey);
  }

  Future<String?> getAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyAccessToken);
  }

  Future<String?> getRefreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyRefreshToken);
  }

  Future<String?> getTenantId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyTenantId);
  }

  Future<String?> getCompanyName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyCompanyName);
  }

  /// Retorna true se o dispositivo já foi ativado (tem chave salva).
  Future<bool> isActivated() async {
    final key = await getActivationKey();
    return key != null && key.isNotEmpty;
  }

  /// Retorna o UUID da filial selecionada pelo vendedor (ou null).
  Future<String?> getBranchId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyBranchId);
  }

  /// Retorna o nome da filial selecionada (ou null).
  Future<String?> getBranchName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyBranchName);
  }

  /// Retorna o erpDeptoPadrao da filial selecionada (ou null).
  Future<int?> getBranchErpDeptoPadrao() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyBranchErpDeptoPadrao);
  }

  /// Retorna o erpEmpresaId da filial selecionada (ou null).
  Future<int?> getBranchErpEmpresaId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyBranchErpEmpresaId);
  }

  /// Retorna true se uma filial já foi selecionada nesta sessão.
  Future<bool> hasBranchSelected() async {
    final id = await getBranchId();
    return id != null && id.isNotEmpty;
  }

  /// Retorna SharedPreferences diretamente para uso como cache de sync.
  ///
  /// Usado pelo SyncService para persistir metadados de sincronização (ex: cached_depto_id).
  /// Retorna null se falhar (não bloqueia o fluxo principal).
  Future<SharedPreferences?> getPrefsForCache() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
  }

  /// Retorna o deptoId da última sincronização bem-sucedida.
  ///
  /// Usado para leitura offline do SQLite — evita dependência do branchId
  /// configurado (que pode ser null em devices recém-instalados sem o Configurator).
  /// Fallback: 1 (PIVETA DIST — filial padrão).
  Future<int> getCachedDeptoId() async {
    final prefs = await getPrefsForCache();
    return prefs?.getInt('cached_depto_id') ?? 1;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Escrita
  // ─────────────────────────────────────────────────────────────────────────

  /// Salva a URL do servidor após validação básica.
  ///
  /// Throws [ArgumentError] se a URL estiver em branco ou sem esquema http/https.
  Future<void> setServerUrl(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) throw ArgumentError('URL não pode estar vazia.');
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      throw ArgumentError('URL deve começar com http:// ou https://');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyServerUrl, trimmed);
  }

  /// Salva a API Key.
  ///
  /// Throws [ArgumentError] se a key estiver em branco.
  Future<void> setApiKey(String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) throw ArgumentError('API Key não pode estar vazia.');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyApiKey, trimmed);
  }

  /// Salva a chave de ativação do dispositivo.
  Future<void> setActivationKey(String key) async {
    final trimmed = key.trim().toUpperCase();
    if (trimmed.isEmpty) throw ArgumentError('Chave de ativação não pode estar vazia.');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyActivationKey, trimmed);
  }

  /// Salva a URL do Identity Server.
  Future<void> setIdentityUrl(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) throw ArgumentError('URL não pode estar vazia.');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyIdentityUrl, trimmed);
  }

  Future<void> setAccessToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAccessToken, token);
  }

  Future<void> setRefreshToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyRefreshToken, token);
  }

  Future<void> setTenantId(String tenantId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyTenantId, tenantId);
  }

  Future<void> setCompanyName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCompanyName, name);
  }

  /// Persiste a filial selecionada pelo vendedor.
  Future<void> setBranch({
    required String branchId, 
    required String branchName,
    required int erpDeptoPadrao,
    required int erpEmpresaId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyBranchId, branchId);
    await prefs.setString(_keyBranchName, branchName);
    await prefs.setInt(_keyBranchErpDeptoPadrao, erpDeptoPadrao);
    await prefs.setInt(_keyBranchErpEmpresaId, erpEmpresaId);
  }

  /// Limpa a filial selecionada (força re-seleção no próximo login).
  Future<void> clearBranch() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyBranchId);
    await prefs.remove(_keyBranchName);
    await prefs.remove(_keyBranchErpDeptoPadrao);
    await prefs.remove(_keyBranchErpEmpresaId);
  }

  /// Remove todas as configurações (volta ao padrão).
  Future<void> resetConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyServerUrl);
    await prefs.remove(_keyApiKey);
  }

  /// Preenche com valores padrão APENAS se ainda não há configuração salva.
  ///
  /// Diferente de [resetConfig], este método respeita configurações existentes.
  Future<void> initializeDefaults() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_keyServerUrl) == null) {
      await prefs.setString(_keyServerUrl, defaultServerUrl);
    }
    if (prefs.getString(_keyApiKey) == null) {
      await prefs.setString(_keyApiKey, defaultApiKey);
    }
  }
}

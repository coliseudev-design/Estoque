/// Configuração persistente do aparelho: ativação no Identity e sessão do operador.
library;

import 'package:shared_preferences/shared_preferences.dart';

class AppConfig {
  AppConfig._(this._prefs);
  final SharedPreferences _prefs;

  static Future<AppConfig> load() async => AppConfig._(await SharedPreferences.getInstance());

  static const defaultIdentityUrl = 'https://adminlicencas.coliseusistemas.com.br';
  static const moduleSlug = 'coliseu-estoque';

  String _s(String k) => _prefs.getString(k) ?? '';
  Future<void> _set(String k, String? v) async =>
      v == null || v.isEmpty ? _prefs.remove(k) : _prefs.setString(k, v);

  // ── Ativação do aparelho (Coliseu.Identity) ──────────────────────────────
  static String _trimUrl(String v) => v.trim().replaceAll(RegExp(r'/+$'), '');

  String get identityUrl => _prefs.getString('identityUrl') ?? defaultIdentityUrl;
  Future<void> setIdentityUrl(String v) => _set('identityUrl', _trimUrl(v));

  /// URL da API do Estoque — vem do módulo no painel (MiddlewareBaseUrl) na ativação.
  String get apiUrl => _s('apiUrl');
  Future<void> setApiUrl(String v) => _set('apiUrl', _trimUrl(v));

  String get tenantId => _s('tenantId');
  String get companyName => _s('companyName');
  String get deviceId => _s('deviceId');
  String get deviceAccessToken => _s('deviceAccessToken');
  String get deviceRefreshToken => _s('deviceRefreshToken');
  bool get isActivated => deviceRefreshToken.isNotEmpty && apiUrl.isNotEmpty;

  Future<void> saveActivation({
    required String tenantId,
    required String companyName,
    required String deviceId,
    required String accessToken,
    required String refreshToken,
    required String apiUrl,
  }) async {
    await _set('tenantId', tenantId);
    await _set('companyName', companyName);
    await _set('deviceId', deviceId);
    await _set('deviceAccessToken', accessToken);
    await _set('deviceRefreshToken', refreshToken);
    if (apiUrl.isNotEmpty) await setApiUrl(apiUrl);
  }

  Future<void> saveDeviceTokens(String access, String refresh) async {
    await _set('deviceAccessToken', access);
    await _set('deviceRefreshToken', refresh);
  }

  Future<void> clearActivation() async {
    for (final k in ['tenantId', 'companyName', 'deviceId', 'deviceAccessToken', 'deviceRefreshToken']) {
      await _prefs.remove(k);
    }
    await clearSession();
  }

  // ── Sessão do operador (token da API do Estoque) ─────────────────────────
  String get sessionToken => _s('sessionToken');
  String get sessionJson => _s('sessionJson');
  String get lastLogin => _s('lastLogin');

  Future<void> saveSession(String token, String json, String login) async {
    await _set('sessionToken', token);
    await _set('sessionJson', json);
    await _set('lastLogin', login);
  }

  Future<void> clearSession() async {
    await _prefs.remove('sessionToken');
    await _prefs.remove('sessionJson');
  }

  // ── Cursor do delta do catálogo ──────────────────────────────────────────
  String cursor(String entity) => _s('cursor.$entity');
  Future<void> setCursor(String entity, String? value) => _set('cursor.$entity', value);

  /// Verificador do PIN para login offline (hash com sal; nunca o PIN em claro).
  String pinVerifier(String login) => _s('pin.${login.toLowerCase()}');
  Future<void> setPinVerifier(String login, String verifier) => _set('pin.${login.toLowerCase()}', verifier);
}

/// Ativação do aparelho e sessão do operador.
///
/// Dois níveis, como no app de vendas:
///  1. APARELHO — vinculado uma vez, de um destes jeitos:
///       a) QR Code / código gerado no painel do Estoque (tela Aparelhos) — padrão;
///       b) chave de ativação do painel de licenças (Coliseu.Identity).
///  2. OPERADOR — entra no turno com usuário + PIN. Online, valida na API;
///     offline, valida contra o verificador salvo no último login online.
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../../models/models.dart';
import '../api/api_client.dart';
import '../config/app_config.dart';
import '../device/device_identity.dart';

const appVersion = '1.1.0';

class SessionController extends ChangeNotifier {
  SessionController(this._config, this._api, this._device) {
    _api.onUnauthorized = _onUnauthorized;
  }

  final AppConfig _config;
  final ApiClient _api;
  final DeviceIdentity _device;

  Session? _session;
  Session? get session => _session;
  bool get isActivated => _config.isActivated;
  bool get isLoggedIn => _session != null;
  /// Sessão restaurada sem validar no servidor (login offline). Envio da fila exige novo login online.
  bool offline = false;
  /// API recusou o token: as leituras continuam na fila até o operador entrar de novo.
  bool sessionExpired = false;

  String get companyName => _session?.companyName.isNotEmpty == true ? _session!.companyName : _config.companyName;
  String get lastLogin => _config.lastLogin;

  void restore() {
    final json = _config.sessionJson;
    if (json.isEmpty || _config.sessionToken.isEmpty) return;
    try {
      _session = Session.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } catch (_) {
      _session = null;
    }
  }

  // ── Pareamento pelo painel do Estoque ────────────────────────────────────

  /// Conteúdo do QR Code do painel: `COLISEU-ESTOQUE|<endereço da API>|<código>`.
  static ({String apiUrl, String code})? parsePairingQr(String raw) {
    final parts = raw.trim().split('|');
    if (parts.length != 3 || parts[0] != 'COLISEU-ESTOQUE') return null;
    return (apiUrl: parts[1].trim(), code: parts[2].trim());
  }

  static String normalizeUrl(String v) {
    var u = v.trim().replaceAll(RegExp(r'/+$'), '');
    if (u.isNotEmpty && !u.startsWith(RegExp(r'https?://'))) u = 'http://$u';
    return u;
  }

  Future<void> pairDevice({required String apiUrl, required String code}) async {
    final url = normalizeUrl(apiUrl);
    await _api.health(url);
    final info = await _device.info();
    final res = await _api.pair(url, {
      'code': code.trim().toUpperCase(),
      'deviceUuid': await _device.id(),
      'model': info.model,
      'os': info.os,
      'appVersion': appVersion,
    });
    await _config.savePairing(
      apiUrl: url,
      tenantId: res['tenantId'].toString(),
      companyName: (res['companyName'] ?? '').toString(),
      deviceId: res['deviceId'].toString(),
      deviceKey: res['deviceKey'].toString(),
    );
    notifyListeners();
  }

  // ── Ativação (Coliseu.Identity) ──────────────────────────────────────────

  Future<void> activate({required String identityUrl, required String activationKey, String apiUrlOverride = ''}) async {
    await _config.setIdentityUrl(identityUrl);
    final info = await _device.info();
    final res = await _api.identityDeviceLogin(_config.identityUrl, {
      'activationKey': activationKey.trim().toUpperCase(),
      'deviceUuid': await _device.id(),
      'model': info.model,
      'os': info.os,
      'appVersion': appVersion,
      'moduleSlug': AppConfig.moduleSlug,
    });
    final apiUrl = apiUrlOverride.trim().isNotEmpty ? apiUrlOverride.trim() : (res['baseUrl'] ?? '').toString();
    if (apiUrl.isEmpty) {
      throw const ApiException('O módulo Estoque não tem URL da API configurada no painel. Informe a URL em "Avançado".');
    }
    await _config.saveActivation(
      tenantId: res['tenantId'].toString(),
      companyName: (res['companyName'] ?? '').toString(),
      deviceId: res['deviceId'].toString(),
      accessToken: res['accessToken'],
      refreshToken: res['refreshToken'],
      apiUrl: apiUrl,
    );
    notifyListeners();
  }

  Future<void> deactivate() async {
    await _config.clearActivation();
    _session = null;
    notifyListeners();
  }

  // ── Login do operador ────────────────────────────────────────────────────

  Future<void> login(String login, String pin) async {
    login = login.trim();
    try {
      final Map<String, dynamic> res;
      if (_config.isPaired) {
        res = await _api.appLogin(_config.deviceKey, login, pin, appVersion);
      } else {
        // JWT do aparelho dura 30 min no Identity: renova a cada login de turno.
        final t = await _api.identityRefresh(_config.identityUrl, _config.deviceRefreshToken);
        await _config.saveDeviceTokens(t['accessToken'], t['refreshToken']);
        res = await _api.operatorLogin(_config.deviceAccessToken, login, pin);
      }
      final s = Session.fromJson(res);
      await _config.saveSession(s.token, jsonEncode(s.toJson()), login);
      await _config.setPinVerifier(login, _makeVerifier(login, pin));
      _session = s;
      offline = false;
      sessionExpired = false;
      notifyListeners();
    } on ApiException catch (e) {
      if (e.isNetwork) {
        _offlineLogin(login, pin);
        return;
      }
      if (e.code == 'DEVICE_REVOKED' || e.code == 'DEVICE_NOT_PAIRED') {
        throw ApiException('${e.message} Use "Desvincular aparelho" no menu ⋮ e pareie de novo.', code: e.code, status: e.status);
      }
      if (e.status == 401 && e.code == null) {
        // /auth/refresh do Identity respondeu 401: aparelho revogado no painel.
        throw const ApiException('Este aparelho foi desvinculado no painel. Solicite nova chave de ativação.');
      }
      rethrow;
    }
  }

  void _offlineLogin(String login, String pin) {
    final verifier = _config.pinVerifier(login);
    final json = _config.sessionJson;
    if (verifier.isEmpty || json.isEmpty || !_checkVerifier(login, pin, verifier)) {
      throw const ApiException('Sem conexão. Só é possível entrar offline com o último usuário que entrou online neste aparelho.');
    }
    final s = Session.fromJson(jsonDecode(json) as Map<String, dynamic>);
    if (s.user.login.toLowerCase() != login.toLowerCase()) {
      throw const ApiException('Sem conexão. Entre com o mesmo usuário do último acesso online.');
    }
    _session = s;
    offline = true;
    notifyListeners();
  }

  Future<void> logout() async {
    await _config.clearSession();
    _session = null;
    notifyListeners();
  }

  void _onUnauthorized() {
    if (_session == null || sessionExpired) return;
    sessionExpired = true;
    notifyListeners();
  }

  // ── Verificador do PIN (login offline) ───────────────────────────────────

  String _makeVerifier(String login, String pin) {
    final salt = base64Url.encode(List<int>.generate(16, (_) => Random.secure().nextInt(256)));
    return '$salt\$${_hash(salt, login, pin)}';
  }

  bool _checkVerifier(String login, String pin, String stored) {
    final parts = stored.split(r'$');
    return parts.length == 2 && parts[1] == _hash(parts[0], login, pin);
  }

  String _hash(String salt, String login, String pin) {
    // Iterado para encarecer força bruta de PIN curto em aparelho perdido.
    List<int> digest = utf8.encode('$salt:${_config.tenantId}:${login.toLowerCase()}:$pin');
    for (var i = 0; i < 20000; i++) {
      digest = sha256.convert(digest).bytes;
    }
    return base64Url.encode(digest);
  }
}

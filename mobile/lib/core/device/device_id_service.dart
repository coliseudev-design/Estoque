/// DeviceIdService — Fornece um identificador único e persistente do dispositivo.
///
/// Estratégia de obtenção (em ordem de prioridade):
///
///   Android: Settings.Secure.ANDROID_ID via MethodChannel nativo Kotlin
///     • Hardware-bound: único por device + assinatura do APK
///     • Sobrevive a reinstalações (diferente de SharedPreferences UUID)
///     • Muda apenas em factory reset (comportamento esperado)
///     • Não requer permissões (AccessLevel.EVERYONE)
///     • Sem dependência de pacote externo
///
///   iOS: identifierForVendor via device_info_plus
///     • Único por vendor, reseta ao desinstalar todos os apps do fabricante
///
///   Web/Desktop: UUID v4 persistido em SharedPreferences (fallback)
///
/// NOTA sobre IMEI: Inacessível em Android 10+ para apps normais.
/// Requer READ_PRIVILEGED_PHONE_STATE (exclusivo de apps do sistema).
/// Settings.Secure.ANDROID_ID é o substituto padrão da indústria.
library;

import 'dart:io' show Platform;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class DeviceIdService {
  static const _kPrefKey   = 'coliseu_device_uuid';
  static const _kChannel   = MethodChannel('coliseu/device');
  static const _uuid       = Uuid();

  final DeviceInfoPlugin _deviceInfo;
  String? _cachedId;

  DeviceIdService({DeviceInfoPlugin? deviceInfo})
      : _deviceInfo = deviceInfo ?? DeviceInfoPlugin();

  /// Retorna o identificador hardware-bound do dispositivo.
  ///
  /// Android: Settings.Secure.ANDROID_ID via MethodChannel nativo
  /// iOS:     identifierForVendor via device_info_plus
  /// Outros:  UUID v4 persistido em SharedPreferences (fallback)
  Future<String> getDeviceId() async {
    if (_cachedId != null) return _cachedId!;

    // ── Android: usar ANDROID_ID via MethodChannel nativo ──────────────
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final androidId = await _kChannel.invokeMethod<String>('getAndroidId');
        if (androidId != null && androidId.isNotEmpty) {
          _cachedId = androidId;
          debugPrint('[DeviceIdService] Android ID (hardware): $_cachedId');
          return _cachedId!;
        }
      } catch (e) {
        debugPrint('[DeviceIdService] Falha no MethodChannel: $e — usando fallback UUID');
      }
    }

    // ── iOS: usar identifierForVendor ──────────────────────────────────
    if (!kIsWeb && Platform.isIOS) {
      try {
        final info = await _deviceInfo.iosInfo;
        final idfv = info.identifierForVendor;
        if (idfv != null && idfv.isNotEmpty) {
          _cachedId = idfv;
          debugPrint('[DeviceIdService] iOS identifierForVendor: $_cachedId');
          return _cachedId!;
        }
      } catch (e) {
        debugPrint('[DeviceIdService] Falha ao obter identifierForVendor: $e — usando fallback UUID');
      }
    }

    // ── Fallback: UUID persistido em SharedPreferences (Web/Desktop) ───
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_kPrefKey);

    if (stored != null && stored.isNotEmpty && _isValidUuid(stored)) {
      _cachedId = stored;
      debugPrint('[DeviceIdService] UUID persistido (fallback): $_cachedId');
      return _cachedId!;
    }

    final newId = _uuid.v4();
    await prefs.setString(_kPrefKey, newId);
    _cachedId = newId;
    debugPrint('[DeviceIdService] Novo UUID gerado (fallback): $newId');
    return _cachedId!;
  }

  /// Verifica se o ID tem formato UUID v4 (8-4-4-4-12 hex com hífens).
  static bool _isValidUuid(String id) {
    final uuidRegex = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      caseSensitive: false,
    );
    return uuidRegex.hasMatch(id);
  }

  /// Retorna modelo e OS do dispositivo para exibição no painel admin.
  Future<({String model, String os})> getDeviceInfo() async {
    try {
      if (!kIsWeb && Platform.isAndroid) {
        final info = await _deviceInfo.androidInfo;
        return (
          model: '${info.manufacturer} ${info.model}',
          os: 'Android ${info.version.release}',
        );
      }
      if (!kIsWeb && Platform.isIOS) {
        final info = await _deviceInfo.iosInfo;
        return (model: info.utsname.machine, os: 'iOS ${info.systemVersion}');
      }
    } catch (_) {}
    return (model: 'Unknown Device', os: 'Unknown OS');
  }
}

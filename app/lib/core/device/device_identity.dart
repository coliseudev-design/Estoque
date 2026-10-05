/// Identificador do aparelho para o vínculo de licença no Coliseu.Identity.
///
/// Mesma estratégia do app de vendas (mobile/): ANDROID_ID via canal nativo — sobrevive
/// a reinstalações, então reinstalar o app não consome outra licença de dispositivo.
library;

import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class DeviceIdentity {
  static const _channel = MethodChannel('coliseu/device');
  static const _prefKey = 'coliseu_device_uuid';
  String? _cached;

  Future<String> id() async {
    if (_cached != null) return _cached!;
    if (Platform.isAndroid) {
      try {
        final androidId = await _channel.invokeMethod<String>('getAndroidId');
        if (androidId != null && androidId.isNotEmpty) return _cached = androidId;
      } catch (_) {/* cai no fallback */}
    }
    if (Platform.isIOS) {
      final idfv = (await DeviceInfoPlugin().iosInfo).identifierForVendor;
      if (idfv != null && idfv.isNotEmpty) return _cached = idfv;
    }
    final prefs = await SharedPreferences.getInstance();
    return _cached = prefs.getString(_prefKey) ?? await () async {
      final v = const Uuid().v4();
      await prefs.setString(_prefKey, v);
      return v;
    }();
  }

  Future<({String model, String os})> info() async {
    try {
      if (Platform.isAndroid) {
        final a = await DeviceInfoPlugin().androidInfo;
        return (model: '${a.manufacturer} ${a.model}', os: 'Android ${a.version.release}');
      }
      if (Platform.isIOS) {
        final i = await DeviceInfoPlugin().iosInfo;
        return (model: i.utsname.machine, os: 'iOS ${i.systemVersion}');
      }
    } catch (_) {}
    return (model: 'Desconhecido', os: Platform.operatingSystem);
  }

  /// Coletores Zebra e Honeywell: o leitor físico chega como teclado (keyboard wedge).
  Future<bool> isRuggedCollector() async {
    if (!Platform.isAndroid) return false;
    try {
      final m = (await DeviceInfoPlugin().androidInfo).manufacturer.toLowerCase();
      return m.contains('zebra') || m.contains('honeywell') || m.contains('datalogic') ||
          m.contains('urovo') || m.contains('chainway') || m.contains('newland');
    } catch (_) {
      return false;
    }
  }
}

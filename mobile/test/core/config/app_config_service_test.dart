/// Testes do AppConfigService.
///
/// Verifica persistência de URL e API Key, defaults, validação e reset.
/// Usa SharedPreferences.setMockInitialValues() para isolar do sistema real.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:coliseu_speed/core/config/app_config_service.dart';

void main() {
  setUp(() {
    // Garante SharedPreferences limpa antes de cada teste
    SharedPreferences.setMockInitialValues({});
  });

  group('AppConfigService', () {
    test('getServerUrl retorna default quando nada salvo', () async {
      final svc = AppConfigService();
      final url = await svc.getServerUrl();
      expect(url, AppConfigService.defaultServerUrl);
    });

    test('getApiKey retorna default quando nada salvo', () async {
      final svc = AppConfigService();
      final key = await svc.getApiKey();
      expect(key, AppConfigService.defaultApiKey);
    });

    test('setServerUrl persiste e getServerUrl retorna novo valor', () async {
      final svc = AppConfigService();
      const url = 'http://192.168.1.100:5000';
      await svc.setServerUrl(url);
      expect(await svc.getServerUrl(), url);
    });

    test('setApiKey persiste e getApiKey retorna novo valor', () async {
      final svc = AppConfigService();
      const key = 'minha-api-key-secreta';
      await svc.setApiKey(key);
      expect(await svc.getApiKey(), key);
    });

    test('setServerUrl lanca ArgumentError para URL vazia', () async {
      final svc = AppConfigService();
      await expectLater(
        svc.setServerUrl(''),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('setServerUrl lanca ArgumentError para URL sem http', () async {
      final svc = AppConfigService();
      await expectLater(
        svc.setServerUrl('ftp://servidor.com'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('setServerUrl aceita https://', () async {
      final svc = AppConfigService();
      await expectLater(
        svc.setServerUrl('https://api.empresa.com'),
        completes,
      );
    });

    test('setApiKey lanca ArgumentError para key vazia', () async {
      final svc = AppConfigService();
      await expectLater(
        svc.setApiKey(''),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('resetConfig restaura defaults', () async {
      final svc = AppConfigService();
      await svc.setServerUrl('http://outro.host:8080');
      await svc.setApiKey('outra-key');
      await svc.resetConfig();

      expect(await svc.getServerUrl(), AppConfigService.defaultServerUrl);
      expect(await svc.getApiKey(),    AppConfigService.defaultApiKey);
    });

    test('setServerUrl faz trim dos espacos', () async {
      final svc = AppConfigService();
      await svc.setServerUrl('  http://192.168.0.1:5000  ');
      expect(await svc.getServerUrl(), 'http://192.168.0.1:5000');
    });
  });
}

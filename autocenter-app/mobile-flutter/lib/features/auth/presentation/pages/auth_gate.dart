import 'dart:async';
import 'package:flutter/material.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'dart:io';
import 'package:dio/dio.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/auth/auth_token_manager.dart';
import '../../../../core/di/injection.dart';
import 'activation_page.dart';
import 'device_blocked_page.dart';
import 'branch_selection_screen.dart';
import 'login_page.dart';
import '../../../home/presentation/pages/home_scaffold.dart';

enum DeviceState { checking, notActivated, blocked, active }

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _tokenManager = getIt<AuthTokenManager>();
  final _apiClient = getIt<ApiClient>();

  DeviceState _state = DeviceState.checking;
  String? _blockedReason;
  bool _hasBranchSelected = false;
  bool _hasVendedorLogged = false;

  @override
  void initState() {
    super.initState();
    _checkDevice();
  }

  Future<void> _setDeviceActive() async {
    final hasBranch = await _tokenManager.hasBranchSelected();
    final vendedorCode = await _tokenManager.getVendedorCode();
    final hasVendedor = vendedorCode != null && vendedorCode.isNotEmpty;
    if (mounted) {
      setState(() {
        _hasBranchSelected = hasBranch;
        _hasVendedorLogged = hasVendedor;
        _state = DeviceState.active;
      });
    }
  }

  Future<String> _getDeviceUuid() async {
    final info = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final android = await info.androidInfo;
      return android.id;
    } else if (Platform.isIOS) {
      final ios = await info.iosInfo;
      return ios.identifierForVendor ?? 'ios-unknown-${DateTime.now().millisecondsSinceEpoch}';
    }
    return 'unknown-${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<void> _checkDevice() async {
    final isActivated = await _tokenManager.isActivated();
    final activationKey = await _tokenManager.getActivationKey();

    if (!isActivated || activationKey == null || activationKey.isEmpty) {
      if (mounted) setState(() => _state = DeviceState.notActivated);
      return;
    }

    try {
      final identityUrl = await _tokenManager.getIdentityUrl();
      if (identityUrl == null || identityUrl.isEmpty) {
        await _setDeviceActive();
        return;
      }

      final deviceUuid = await _getDeviceUuid();
      final packageInfo = await PackageInfo.fromPlatform();
      final deviceInfo = DeviceInfoPlugin();
      String? model;
      String? osVersion;

      if (Platform.isAndroid) {
        final android = await deviceInfo.androidInfo;
        model = '${android.brand} ${android.model}';
        osVersion = 'Android ${android.version.release}';
      } else if (Platform.isIOS) {
        final ios = await deviceInfo.iosInfo;
        model = ios.model;
        osVersion = 'iOS ${ios.systemVersion}';
      }

      final identityClient = _apiClient.createIdentityClient(identityUrl);
      final resp = await identityClient.post(
        '/auth/device-login',
        data: {
          'activationKey': activationKey,
          'deviceUuid': deviceUuid,
          'model': model,
          'os': osVersion,
          'appVersion': packageInfo.version,
          'moduleSlug': 'autocenter',
        },
      );

      if (resp.statusCode == 200 || resp.statusCode == 201) {
        final data = resp.data as Map<String, dynamic>;
        
        // Renova tokens e base URL caso tenham mudado
        await _tokenManager.saveToken(data['accessToken']);
        await _tokenManager.saveRefreshToken(data['refreshToken']);
        
        final newBaseUrl = data['baseUrl'] as String?;
        if (newBaseUrl != null && newBaseUrl.isNotEmpty) {
          final resolvedUrl = (newBaseUrl.contains('middleware') || newBaseUrl.contains('localhost'))
              ? 'https://autocenter.coliseusistemas.com.br'
              : newBaseUrl;
          await _tokenManager.saveBaseUrl(resolvedUrl);
          _apiClient.updateBaseUrl('$resolvedUrl/api');
        }

        await _setDeviceActive();
      }
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      if (statusCode == 403 || statusCode == 401) {
        final errorMsg = e.response?.data?['error'] ?? 'Dispositivo não autorizado.';
        
        // Limpa tokens mas preserva chave para a tela de bloqueio
        await _tokenManager.deleteToken();
        
        if (mounted) {
          setState(() {
            _state = DeviceState.blocked;
            _blockedReason = errorMsg.toString();
          });
        }
      } else {
        // Erro de rede (permitir offline-first)
        await _setDeviceActive();
      }
    } catch (_) {
      await _setDeviceActive();
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_state) {
      case DeviceState.checking:
        return const Scaffold(
          body: Center(
            child: CircularProgressIndicator(color: Color(0xFF1C6EF2)),
          ),
        );

      case DeviceState.notActivated:
        return const ActivationPage();

      case DeviceState.blocked:
        return DeviceBlockedPage(
          reason: _blockedReason,
          onReactivate: () {
            _tokenManager.clearAll();
            setState(() => _state = DeviceState.notActivated);
          },
        );

      case DeviceState.active:
        if (!_hasBranchSelected) {
          return const BranchSelectionScreen();
        }
        if (!_hasVendedorLogged) {
          return const LoginPage();
        }
        return const HomeScaffold();
    }
  }
}

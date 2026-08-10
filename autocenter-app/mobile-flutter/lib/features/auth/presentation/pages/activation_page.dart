import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'dart:io';
import 'package:dio/dio.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/auth/auth_token_manager.dart';
import '../../data/datasources/activation_remote_datasource.dart';
import '../../../home/presentation/pages/home_scaffold.dart';
import 'branch_selection_screen.dart';
import 'setup_page.dart';

/// Tela de ativação do AutoCenter App via Coliseu Identity Server.
///
/// Fluxo:
/// 1. Usuário insere a URL do Identity Server e a Chave de Ativação (10 chars)
/// 2. App obtém o UUID do dispositivo (Android ID)
/// 3. POST para /auth/device-login com moduleSlug: 'autocenter'
/// 4. Resposta inclui JWT + URL do Middleware AutoCenter
/// 5. Dados salvos no SecureStorage → navegação para Home
// ...
import '../../../../core/di/injection.dart';
// ...

class ActivationPage extends StatefulWidget {
  const ActivationPage({super.key});

  @override
  State<ActivationPage> createState() => _ActivationPageState();
}

class _ActivationPageState extends State<ActivationPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _identityUrlController = TextEditingController(
    text: 'https://adminlicencas.coliseusistemas.com.br',
  );
  final _activationKeyController = TextEditingController();

  bool _loading = false;
  String? _errorMsg;
  String? _successMsg;

  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _identityUrlController.dispose();
    _activationKeyController.dispose();
    super.dispose();
  }

  Future<String> _getDeviceUuid() async {
    final info = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final android = await info.androidInfo;
      return android.id; // Android ID único por dispositivo + app
    } else if (Platform.isIOS) {
      final ios = await info.iosInfo;
      return ios.identifierForVendor ?? 'ios-unknown-${DateTime.now().millisecondsSinceEpoch}';
    }
    return 'unknown-${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<void> _handleActivate() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _errorMsg = null;
      _successMsg = null;
    });

    try {
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

      final apiClient = getIt<ApiClient>();
      final tokenManager = getIt<AuthTokenManager>();

      final dataSource = ActivationRemoteDataSourceImpl(apiClient: apiClient);
      final result = await dataSource.activateDevice(
        identityBaseUrl: _identityUrlController.text.trim(),
        activationKey: _activationKeyController.text.trim().toUpperCase(),
        deviceUuid: deviceUuid,
        model: model,
        os: osVersion,
        appVersion: packageInfo.version,
      );

      final resolvedBaseUrl = (result.baseUrl.contains('middleware') || result.baseUrl.contains('localhost'))
          ? 'https://autocenter.coliseusistemas.com.br'
          : result.baseUrl;

      // Salva todos os dados no SecureStorage
      await tokenManager.saveSession(
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
        baseUrl: resolvedBaseUrl,
        companyName: result.companyName,
        tenantId: result.tenantId,
        deviceId: result.deviceId,
        identityUrl: _identityUrlController.text.trim(),
      );

      // Atualiza o ApiClient com a URL correta do middleware AutoCenter
      apiClient.updateBaseUrl('$resolvedBaseUrl/api');

      setState(() {
        _successMsg = 'Ativação concluída! Bem-vindo ao ${result.companyName} 🎉';
      });

      await Future.delayed(const Duration(seconds: 1));
      
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const BranchSelectionScreen()),
        );
      }
    } on DioException catch (e) {
      String msg = 'Erro ao ativar dispositivo.';
      final serverError = e.response?.data is Map ? e.response?.data['error'] : null;
      
      if (serverError != null) {
        msg = serverError.toString();
      } else if (e.response?.statusCode == 403 || e.response?.statusCode == 401) {
        msg = 'Chave de ativação inválida ou módulo não habilitado.';
      } else if (e.type == DioExceptionType.connectionTimeout || 
                 e.type == DioExceptionType.receiveTimeout || 
                 e.message?.contains('SocketException') == true) {
        msg = 'Não foi possível conectar ao servidor. Verifique a URL e sua conexão.';
      } else {
        msg = 'Erro ${e.response?.statusCode ?? ''}: ${e.message}';
      }
      setState(() => _errorMsg = msg);
    } catch (e) {
      setState(() => _errorMsg = 'Erro interno: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;

    return Scaffold(
      backgroundColor: isLight ? const Color(0xFFF5F7FF) : const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(
              Icons.settings_outlined,
              color: isLight ? const Color(0xFF64748B) : const Color(0xFF8B9AB1),
            ),
            tooltip: 'Configurações de Rede',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SetupPage()),
              );
            },
          ),
        ],
      ),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // ── Logo ────────────────────────────────────────────────
                    Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF1C6EF2), Color(0xFF0D4CB5)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF1C6EF2).withValues(alpha: 0.35),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.car_repair, size: 44, color: Colors.white),
                    ),
                    const SizedBox(height: 24),

                    Text(
                      'AutoCenter',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: isLight ? const Color(0xFF1A1A2E) : Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Ativação do Dispositivo',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: isLight ? const Color(0xFF64748B) : const Color(0xFF8B9AB1),
                      ),
                    ),

                    const SizedBox(height: 40),

                    // ── Card ────────────────────────────────────────────────
                    Container(
                      decoration: BoxDecoration(
                        color: isLight ? Colors.white : const Color(0xFF161B26),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: isLight ? 0.07 : 0.3),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(28),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [

                            _sectionLabel('Chave de Ativação do Dispositivo'),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _activationKeyController,
                              textCapitalization: TextCapitalization.characters,
                              maxLength: 10,
                              enabled: !_loading,
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                              ],
                              decoration: _inputDecoration(
                                hint: 'Ex: AB12CD34EF',
                                icon: Icons.key_outlined,
                              ).copyWith(
                                counterText: '',
                                helperText: 'Chave gerada pelo administrador no painel.',
                              ),
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 4,
                              ),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) return 'Informe a chave de ativação.';
                                if (v.trim().length != 10) return 'A chave deve ter exatamente 10 caracteres.';
                                return null;
                              },
                            ),

                            const SizedBox(height: 28),

                            // ── Botão principal ──────────────────────────
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: ElevatedButton(
                                onPressed: _loading ? null : _handleActivate,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF1C6EF2),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  elevation: 2,
                                ),
                                child: _loading
                                    ? const SizedBox(
                                        width: 22, height: 22,
                                        child: CircularProgressIndicator(
                                          color: Colors.white, strokeWidth: 2.5,
                                        ),
                                      )
                                    : const Text(
                                        'Ativar Dispositivo',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // ── Mensagens de feedback ────────────────────────────────
                    if (_errorMsg != null) ...[
                      const SizedBox(height: 16),
                      _FeedbackBanner(message: _errorMsg!, isError: true),
                    ],
                    if (_successMsg != null) ...[
                      const SizedBox(height: 16),
                      _FeedbackBanner(message: _successMsg!, isError: false),
                    ],

                    const SizedBox(height: 32),
                    Text(
                      'Coliseu Sistemas · AutoCenter v1.0',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isLight ? const Color(0xFF94A3B8) : const Color(0xFF4B5563),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: Color(0xFF64748B),
      letterSpacing: 0.3,
    ),
  );

  InputDecoration _inputDecoration({required String hint, required IconData icon}) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, size: 20, color: const Color(0xFF94A3B8)),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF1C6EF2), width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFEF4444)),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }
}

class _FeedbackBanner extends StatelessWidget {
  final String message;
  final bool isError;

  const _FeedbackBanner({required this.message, required this.isError});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isError
            ? const Color(0xFFFEF2F2)
            : const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isError ? const Color(0xFFFECACA) : const Color(0xFFBBF7D0),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            color: isError ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 13,
                color: isError ? const Color(0xFF991B1B) : const Color(0xFF166534),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

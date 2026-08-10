import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'dart:io';
import 'package:dio/dio.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/auth/auth_token_manager.dart';
import '../../data/datasources/activation_remote_datasource.dart';
import '../../../../core/di/injection.dart';
import 'branch_selection_screen.dart';

class SetupPage extends StatefulWidget {
  const SetupPage({super.key});

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  final _formKey = GlobalKey<FormState>();
  final _tokenManager = getIt<AuthTokenManager>();
  final _apiClient = getIt<ApiClient>();

  final _identityUrlController = TextEditingController();
  final _activationKeyController = TextEditingController();
  final _middlewareUrlController = TextEditingController();

  bool _loading = false;
  bool _testOk = false;
  String? _errorMsg;
  String? _successMsg;
  ActivationResult? _activationResult;

  @override
  void initState() {
    super.initState();
    _loadCurrentConfig();
  }

  Future<void> _loadCurrentConfig() async {
    final savedIdentityUrl = await _tokenManager.getIdentityUrl();
    final savedKey = await _tokenManager.getActivationKey();
    final savedMiddlewareUrl = await _tokenManager.getBaseUrl();
    
    setState(() {
      _identityUrlController.text = savedIdentityUrl ?? 'https://adminlicencas.coliseusistemas.com.br';
      _activationKeyController.text = savedKey ?? '';
      _middlewareUrlController.text = savedMiddlewareUrl ?? 'http://localhost:3100';
    });
  }

  @override
  void dispose() {
    _identityUrlController.dispose();
    _activationKeyController.dispose();
    _middlewareUrlController.dispose();
    super.dispose();
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

  Future<void> _handleTestConnection() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _errorMsg = null;
      _successMsg = null;
      _testOk = false;
      _activationResult = null;
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

      final dataSource = ActivationRemoteDataSourceImpl(apiClient: _apiClient);
      final result = await dataSource.activateDevice(
        identityBaseUrl: _identityUrlController.text.trim(),
        activationKey: _activationKeyController.text.trim().toUpperCase(),
        deviceUuid: deviceUuid,
        model: model,
        os: osVersion,
        appVersion: packageInfo.version,
      );

      final resolvedUrl = (result.baseUrl.contains('middleware') || result.baseUrl.contains('localhost'))
          ? 'https://autocenter.coliseusistemas.com.br'
          : result.baseUrl;

      setState(() {
        _testOk = true;
        _activationResult = result;
        _middlewareUrlController.text = resolvedUrl; // Popula com a URL resolvida pela Identity
        _successMsg = 'Conexão OK! Empresa vinculada: ${result.companyName}';
      });
    } on DioException catch (e) {
      String msg = 'Falha na conexão.';
      final serverError = e.response?.data is Map ? e.response?.data['error'] : null;
      
      if (serverError != null) {
        msg = serverError.toString();
      } else if (e.response?.statusCode == 403 || e.response?.statusCode == 401) {
        msg = 'Chave inválida ou módulo inativo.';
      } else {
        msg = 'Erro ${e.response?.statusCode ?? ""}: ${e.message}';
      }
      setState(() => _errorMsg = msg);
    } catch (e) {
      setState(() => _errorMsg = 'Erro: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _handleSave() async {
    final identityUrl = _identityUrlController.text.trim();
    final activationKey = _activationKeyController.text.trim().toUpperCase();
    final middlewareUrl = _middlewareUrlController.text.trim();

    if (identityUrl.isEmpty || activationKey.isEmpty || middlewareUrl.isEmpty) {
      setState(() => _errorMsg = 'Todos os campos são obrigatórios.');
      return;
    }

    setState(() => _loading = true);
    try {
      final result = _activationResult;
      if (result != null) {
        // Salva a sessão completa no SecureStorage usando a URL editada do campo
        await _tokenManager.saveSession(
          accessToken: result.accessToken,
          refreshToken: result.refreshToken,
          baseUrl: middlewareUrl,
          companyName: result.companyName,
          tenantId: result.tenantId,
          deviceId: result.deviceId,
          identityUrl: identityUrl,
        );
      } else {
        // Apenas atualiza as URLs base e Identity no storage
        await _tokenManager.saveIdentityUrl(identityUrl);
        await _tokenManager.saveBaseUrl(middlewareUrl);
      }

      // Salva a chave de ativação
      await _tokenManager.saveActivationKey(activationKey);

      // Atualiza a base URL do ApiClient global
      _apiClient.updateBaseUrl('${middlewareUrl}/api');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Configurações salvas e aplicadas!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const BranchSelectionScreen()),
        );
      }
    } catch (e) {
      setState(() {
        _errorMsg = 'Erro ao salvar: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;

    return Scaffold(
      backgroundColor: isLight ? const Color(0xFFF5F7FF) : const Color(0xFF0D1117),
      appBar: AppBar(
        title: const Text('Configurações do Servidor'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: isLight ? Colors.black87 : Colors.white,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C6EF2).withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.cloud_sync_outlined, size: 48, color: Color(0xFF1C6EF2)),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Configuração de Rede',
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Configure os servidores de ativação e o endereço do Middleware AutoCenter.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  Container(
                    decoration: BoxDecoration(
                      color: isLight ? Colors.white : const Color(0xFF161B26),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(isLight ? 0.05 : 0.2),
                          blurRadius: 20,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(24),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionLabel('Endereço do Identity Server'),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _identityUrlController,
                            keyboardType: TextInputType.url,
                            enabled: !_loading,
                            decoration: _inputDecoration(
                              hint: 'https://...',
                              icon: Icons.link,
                            ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) return 'Informe a URL do Identity.';
                              if (!v.startsWith('http://') && !v.startsWith('https://')) {
                                return 'A URL deve iniciar com http:// ou https://';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 20),
                          _sectionLabel('Chave de Ativação (10 Caracteres)'),
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
                            ).copyWith(counterText: ''),
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2,
                            ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) return 'Informe a chave.';
                              if (v.trim().length != 10) return 'A chave deve ter 10 caracteres.';
                              return null;
                            },
                          ),
                          const SizedBox(height: 20),
                          _sectionLabel('URL do Middleware (VPS)'),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _middlewareUrlController,
                            keyboardType: TextInputType.url,
                            enabled: !_loading,
                            decoration: _inputDecoration(
                              hint: 'https://...',
                              icon: Icons.computer_rounded,
                            ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) return 'Informe a URL do Middleware.';
                              return null;
                            },
                          ),
                          const SizedBox(height: 28),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _loading ? null : _handleTestConnection,
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  child: const Text('Testar Conexão'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: _loading ? null : _handleSave,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF1C6EF2),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  child: const Text('Salvar'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_errorMsg != null) ...[
                    const SizedBox(height: 16),
                    _FeedbackBanner(message: _errorMsg!, isError: true),
                  ],
                  if (_successMsg != null) ...[
                    const SizedBox(height: 16),
                    _FeedbackBanner(message: _successMsg!, isError: false),
                  ],
                ],
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
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
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
        color: isError ? const Color(0xFFFEF2F2) : const Color(0xFFF0FDF4),
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

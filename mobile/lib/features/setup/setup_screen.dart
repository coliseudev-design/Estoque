/// SetupScreen — Tela de configuração inicial do servidor e API Key.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../../core/config/app_config_service.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/device/device_id_service.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_typography.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _formKey   = GlobalKey<FormState>();
  final _urlCtrl   = TextEditingController();
  final _keyCtrl   = TextEditingController();

  bool    _saving     = false;
  bool    _testing    = false;
  String? _testResult;
  bool    _testOk     = false;

  Map<String, dynamic>? _deviceLoginData;
  bool    _keyVisible = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentConfig();
  }

  Future<void> _loadCurrentConfig() async {
    final config = GetIt.I<AppConfigService>();
    _urlCtrl.text = await config.getIdentityUrl();
    _keyCtrl.text = await config.getActivationKey() ?? '';
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _keyCtrl.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _testing = true; _testResult = null; _deviceLoginData = null; });
    
    try {
      final testDio = Dio(BaseOptions(
        baseUrl:        _urlCtrl.text.trim(),
        connectTimeout: const Duration(seconds: 10),
      ));

      // Obter UUID e metadata do dispositivo
      final deviceIdService = DeviceIdService();
      final uuid = await deviceIdService.getDeviceId();
      final info = await deviceIdService.getDeviceInfo();

      final resp = await testDio.post('/auth/device-login', data: {
        'activationKey': _keyCtrl.text.trim().toUpperCase(),
        'deviceUuid':    uuid,
        'model':         info.model,
        'os':            info.os,
        'appVersion':    '1.0.0', // TODO: Pegar do package_info_plus
        'moduleSlug':    'coliseuspeed',
      });

      if (resp.statusCode == 200 || resp.statusCode == 201) {
         _deviceLoginData = resp.data as Map<String, dynamic>;
         setState(() {
            _testOk     = true;
            _testResult = 'Dispositivo vinculado à empresa: ${_deviceLoginData!["companyName"]}';
         });
      } else {
         setState(() {
            _testOk     = false;
            _testResult = 'Erro no servidor: ${resp.statusCode}';
         });
      }
    } on DioException catch (e) {
      final msg = e.response?.data?['error'] ?? 'Falha na conexão';
      setState(() { _testOk = false; _testResult = 'Erro: $msg'; });
    } catch (_) {
      setState(() { _testOk = false; _testResult = 'Falha: verifique a URL e a conexão com internet'; });
    } finally {
      setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    if (_deviceLoginData == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, teste a conexão primeiro.'), backgroundColor: Colors.orange));
      return;
    }

    setState(() => _saving = true);
    try {
      final config = GetIt.I<AppConfigService>();
      
      final identityUrl = _urlCtrl.text.trim();
      final activationKey = _keyCtrl.text.trim().toUpperCase();
      
      final accessToken = _deviceLoginData!['accessToken'];
      final refreshToken = _deviceLoginData!['refreshToken'];
      final tenantId = _deviceLoginData!['tenantId'];
      final companyName = _deviceLoginData!['companyName'];
      
      // O middleware/sales api url vem do Identity.
      // Se o Identity retorna hostname Docker interno (ex: http://middleware:3000),
      // usamos a URL pública padrão — o celular não resolve nomes Docker.
      final rawSalesUrl = _deviceLoginData!['baseUrl'] as String?;
      final salesApiUrl = (rawSalesUrl != null && !rawSalesUrl.contains('middleware:'))
          ? rawSalesUrl
          : AppConfigService.defaultServerUrl;
      
      await config.setIdentityUrl(identityUrl);
      await config.setActivationKey(activationKey);
      await config.setServerUrl(salesApiUrl);
      await config.setAccessToken(accessToken);
      await config.setRefreshToken(refreshToken);

      // ── Isolamento multi-tenant: apaga banco local se a empresa mudou ──────
      // Garante que dados da empresa anterior NUNCA apareçam para a nova empresa.
      final previousTenantId = await config.getTenantId();
      if (tenantId != null && previousTenantId != null && previousTenantId != tenantId) {
        debugPrint('[SetupScreen] Empresa alterada ($previousTenantId → $tenantId): limpando banco local...');
        await DatabaseHelper().clearAllTables();
      }

      await config.setTenantId(tenantId);
      await config.setCompanyName(companyName);

      // Atualiza Dio global em memória para o Sales API
      final dio = GetIt.I<Dio>();
      dio.options.baseUrl = salesApiUrl;

      // Nota: o JwtInterceptor já vai injetar automaticamente o token
      // na próxima request porque ele lê direto da SessionService (que vamos atualizar).
      // Porém, como o JwtInterceptor atualmente pega o token da sessão do VENDEDOR,
      // precisaremos ajustar o SessionService/JwtInterceptor para ter acesso a este token do device.

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Dispositivo ativado com sucesso!'),
        backgroundColor: Colors.green,
      ));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao salvar: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(
        title: const Text('Configuracoes do Servidor'),
        backgroundColor: AppColors.backgroundPrimary,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.cloud_sync_outlined,
                        size: 48, color: AppColors.primary),
                  ),
                ),
                const SizedBox(height: 24),
                Text('Conectar ao servidor',
                    style: AppTypography.headingLarge.copyWith(fontWeight: FontWeight.w700),
                    textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(
                  'Configure o endereco do servidor e a chave de acesso \nfornecida pelo administrador.',
                  style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                // O campo de URL do Identity foi oculto para simplificar a vida do usuário.
                // Ele usará automaticamente a 'defaultIdentityUrl' definida no AppConfigService.

                Text('Chave de Ativação', style: AppTypography.label),
                const SizedBox(height: 8),
                TextFormField(
                  controller:  _keyCtrl,
                  obscureText: !_keyVisible,
                  autocorrect: false,
                  decoration: InputDecoration(
                    hintText:  '0675B1DC61',
                    prefixIcon: const Icon(Icons.key_outlined),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: AppColors.backgroundSecondary,
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Chave de Ativação obrigatória';
                    return null;
                  },
                ),
                const SizedBox(height: 24),

                if (_testResult != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: (_testOk ? Colors.green : Colors.red).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: (_testOk ? Colors.green : Colors.red).withOpacity(0.3)),
                    ),
                    child: Text(_testResult!,
                      style: TextStyle(
                        color: _testOk ? Colors.green.shade700 : Colors.red.shade700,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      )),
                  ),
                  const SizedBox(height: 16),
                ],

                OutlinedButton.icon(
                  onPressed: _testing ? null : _testConnection,
                  icon: _testing
                      ? const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.wifi_find_outlined),
                  label: Text(_testing ? 'Testando...' : 'Testar Conexao'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),

                ElevatedButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save_outlined),
                  label: Text(_saving ? 'Salvando...' : 'Salvar e Conectar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

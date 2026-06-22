/// ActivationScreen — Tela de primeira ativação do dispositivo.
///
/// Fluxo:
/// 1. Usuário recebe a CHAVE DE ATIVAÇÃO de 10 chars gerada no painel Admin
/// 2. Digita a chave nesta tela
/// 3. App envia para o Identity Server com o UUID do hardware
/// 4. Backend vincula UUID à chave → dispositivo fica "Ativo"
/// 5. Chave salva localmente — nunca mais precisa digitar
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:get_it/get_it.dart';
import '../../core/config/app_config_service.dart';
import '../../core/database/database_helper.dart';
import '../../core/device/device_id_service.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_typography.dart';
import '../auth/login_screen.dart';

class ActivationScreen extends StatefulWidget {
  /// Chamado quando a ativação for bem-sucedida.
  /// O pai (_AuthGate) reage tornando o LoginScreen visível.
  final VoidCallback? onActivated;

  const ActivationScreen({super.key, this.onActivated});

  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<ActivationScreen> {
  final _controller = TextEditingController();
  final _focus      = FocusNode();
  final _config     = AppConfigService();

  bool    _isLoading = false;
  String? _errorMsg;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Envia a chave de ativação para o Identity Server.
  Future<void> _activate() async {
    final key = _controller.text.trim().toUpperCase();
    if (key.isEmpty) {
      setState(() => _errorMsg = 'Digite a chave de ativação.');
      return;
    }
    if (key.length != 10) {
      setState(() => _errorMsg = 'A chave deve ter exatamente 10 caracteres.');
      return;
    }

    setState(() { _isLoading = true; _errorMsg = null; });

    try {
      final deviceSvc    = DeviceIdService();
      final deviceUuid   = await deviceSvc.getDeviceId();
      final deviceInfo   = await deviceSvc.getDeviceInfo();
      final identityUrl  = await _config.getIdentityUrl();

      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
      ));

      final response = await dio.post(
        '$identityUrl/auth/device-login',
        data: {
          'activationKey': key,
          'deviceUuid'   : deviceUuid,
          'model'        : deviceInfo.model,
          'os'           : deviceInfo.os,
          'appVersion'   : '1.0.0',
          'moduleSlug'   : 'coliseuspeed',
        },
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;

        // Salva a chave de ativação
        await _config.setActivationKey(key);

        // Salva tokens e dados do Identity (mesmo fluxo do SetupScreen._save)
        final accessToken  = data['accessToken']  as String?;
        final refreshToken = data['refreshToken'] as String?;
        final tenantId     = data['tenantId']     as String?;
        final companyName  = data['companyName']  as String?;
        // salesApiUrl: se Identity retorna hostname Docker interno, usa URL pública padrão
        final rawSalesUrl = data['baseUrl'] as String?;
        final salesApiUrl = (rawSalesUrl != null && !rawSalesUrl.contains('middleware:'))
            ? rawSalesUrl
            : AppConfigService.defaultServerUrl;

        if (accessToken != null)  await _config.setAccessToken(accessToken);
        if (refreshToken != null) await _config.setRefreshToken(refreshToken);

        // ── Isolamento multi-tenant: limpa banco se a empresa mudou ────────────
        if (tenantId != null) {
          final previousTenantId = await _config.getTenantId();
          if (previousTenantId != null && previousTenantId != tenantId) {
            debugPrint('[ActivationScreen] Empresa alterada ($previousTenantId → $tenantId): limpando banco local...');
            await DatabaseHelper().clearAllTables();
          }
          await _config.setTenantId(tenantId);
        }
        if (companyName != null)  await _config.setCompanyName(companyName);
        await _config.setServerUrl(salesApiUrl);

        // Atualiza Dio global em memória para que pullSellers() use a URL correta
        if (salesApiUrl != null) {
          try {
            final globalDio = GetIt.I<Dio>();
            globalDio.options.baseUrl = salesApiUrl;
          } catch (_) {
            // GetIt pode não estar configurado ainda em cenários de teste
          }
        }

        if (!mounted) return;
        if (widget.onActivated != null) {
          // Notifica o pai (_AuthGate) para reconstruir o gate
          widget.onActivated!();
        } else {
          // Fallback: navega diretamente para o login
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
          );
        }
      } else {
        setState(() => _errorMsg = 'Resposta inesperada do servidor.');
      }
    } on DioException catch (e) {
      final msg = e.response?.data?['error']
          ?? e.response?.data?['message']
          ?? 'Falha ao conectar ao servidor de licenças.';
      setState(() => _errorMsg = msg.toString());
    } catch (e) {
      setState(() => _errorMsg = 'Erro: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ── Logo / Ícone ──────────────────────────────────────
                Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.phonelink_lock_outlined,
                    size: 40,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 24),

                // ── Título ────────────────────────────────────────────
                Text(
                  'Ativar Dispositivo',
                  style: AppTypography.headlineMedium.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Digite a chave de ativação fornecida pelo\nadministrador do sistema.',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),

                // ── Campo da chave ────────────────────────────────────
                TextField(
                  controller: _controller,
                  focusNode: _focus,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[A-Fa-f0-9]')),
                    LengthLimitingTextInputFormatter(10),
                  ],
                  style: AppTypography.headlineMedium.copyWith(
                    letterSpacing: 6,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    hintText: 'XXXXXXXXXX',
                    hintStyle: AppTypography.headlineMedium.copyWith(
                      letterSpacing: 6,
                      color: AppColors.textSecondary.withOpacity(0.4),
                    ),
                    filled: true,
                    fillColor: AppColors.backgroundSecondary,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: AppColors.primary, width: 2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 20,
                    ),
                  ),
                  onSubmitted: (_) => _isLoading ? null : _activate(),
                ),
                const SizedBox(height: 8),

                // ── Mensagem de erro ──────────────────────────────────
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _errorMsg != null
                      ? Container(
                          key: ValueKey(_errorMsg),
                          margin: const EdgeInsets.only(top: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.error.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline,
                                  size: 18, color: AppColors.error),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMsg!,
                                  style: AppTypography.bodySmall.copyWith(
                                    color: AppColors.error,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                const SizedBox(height: 32),

                // ── Botão de confirmar ────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _activate,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor:
                          AppColors.textSecondary.withOpacity(0.2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 22, height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Ativar Dispositivo',
                            style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(height: 16),

                // ── Info ──────────────────────────────────────────────
                Text(
                  'A chave é gerada no painel de administração.\n'
                  'Cada chave só pode ser usada em um dispositivo.',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

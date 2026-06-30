/// ServerConfigScreen — Tela de configuração da URL do servidor e API Key.
///
/// Permite que o vendedor (ou administrador) configure:
/// - URL do servidor middleware (ex: http://192.168.1.100:5000)
/// - API Key compartilhada com o middleware
///
/// As configurações são persistidas no SharedPreferences via AppConfigService.
/// As mudanças são aplicadas imediatamente ao Dio singleton registrado
/// no service locator — não é necessário reiniciar o app.
///
/// Acesso: SellerProfileScreen → botão "Configurar Servidor"
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../core/config/app_config_service.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_typography.dart';

class ServerConfigScreen extends StatefulWidget {
  const ServerConfigScreen({super.key});

  @override
  State<ServerConfigScreen> createState() => _ServerConfigScreenState();
}

class _ServerConfigScreenState extends State<ServerConfigScreen> {
  final _config      = GetIt.I<AppConfigService>();
  final _urlCtrl     = TextEditingController();
  final _keyCtrl     = TextEditingController();
  final _formKey     = GlobalKey<FormState>();

  bool _loading  = true;
  bool _saving   = false;
  bool _showKey  = false;

  @override
  void initState() {
    super.initState();
    _loadCurrent();
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _keyCtrl.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Carregamento
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _loadCurrent() async {
    final url = await _config.getServerUrl();
    final key = await _config.getApiKey();
    if (!mounted) return;
    setState(() {
      _urlCtrl.text = url;
      _keyCtrl.text = key;
      _loading = false;
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Ações
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);
    try {
      final newUrl = _urlCtrl.text.trim();
      final newKey = _keyCtrl.text.trim();
      await _config.setServerUrl(newUrl);
      await _config.setApiKey(newKey);

      // Hot-patch Dio — aplica imediatamente sem reiniciar o app
      final dio = GetIt.I<Dio>();
      dio.options.baseUrl = newUrl;
      dio.options.headers['API-Key'] = newKey;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
          '✓ Configurações aplicadas! Você já pode sincronizar.',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: AppColors.syncSuccess,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 4),
      ));
    } on ArgumentError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.message as String),
        backgroundColor: AppColors.syncError,
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Restaurar padrões?'),
        content: const Text(
          'A URL e o Número da Chave voltarão aos valores padrão de desenvolvimento.\n\n'
          'O app precisará ser reiniciado para aplicar as mudanças.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.syncError),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restaurar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;

    await _config.resetConfig();
    await _loadCurrent();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Configurações restauradas para o padrão.'),
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuração do Servidor'),
      ),
      backgroundColor: AppColors.surfaceSecondary,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Aviso de reinicialização ─────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.syncInProgressLight,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.syncInProgress),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded,
                          color: AppColors.syncInProgress, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'As mudanças são aplicadas imediatamente ao salvar.',
                          style: AppTypography.badge
                              .copyWith(color: AppColors.syncInProgress),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // ── Formulário ──────────────────────────────────────────────
                Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 10),

                      Text('Número da Chave', style: AppTypography.fieldLabel),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller:   _keyCtrl,
                        obscureText:  !_showKey,
                        autocorrect:  false,
                        decoration: _inputDecoration(
                          hint: 'dev-coliseu-speed-...',
                          icon: Icons.vpn_key_rounded,
                          suffix: IconButton(
                            icon: Icon(
                              _showKey
                                  ? Icons.visibility_off_rounded
                                  : Icons.visibility_rounded,
                              color: AppColors.textSecondary,
                              size: 20,
                            ),
                            onPressed: () =>
                                setState(() => _showKey = !_showKey),
                          ),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'O Número da Chave não pode estar vazio.';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                // ── Botões ──────────────────────────────────────────────────
                ElevatedButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.save_rounded),
                  label: Text(_saving ? 'Salvando…' : 'Salvar Configurações'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.actionPrimary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _reset,
                  icon: const Icon(Icons.restore_rounded),
                  label: const Text('Restaurar Padrões'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    minimumSize: const Size.fromHeight(44),
                  ),
                ),
              ],
            ),
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) =>
      InputDecoration(
        hintText:       hint,
        hintStyle:      AppTypography.body.copyWith(color: AppColors.textTertiary),
        prefixIcon:     Icon(icon, size: 20, color: AppColors.textSecondary),
        suffixIcon:     suffix,
        filled:         true,
        fillColor:      AppColors.surfacePrimary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide:   const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide:   const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.actionPrimary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide:   const BorderSide(color: AppColors.syncError),
        ),
      );
}

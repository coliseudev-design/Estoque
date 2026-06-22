/// LoginScreen — Tela de autenticação do vendedor por PIN (integração ERP).
///
/// Fluxo ERP:
/// 1. App carrega vendedores da tabela `sellers` (sincronizados do PIVETA.FDB)
/// 2. Se há apenas um vendedor, pula direto para o PIN
/// 3. Se há múltiplos, exibe lista de seleção
/// 4. Vendedor digitia o PIN (MOB_SENHA do ERP)
/// 5. SessionService.loginWithERP() valida localmente (offline-first)
///
/// UX:
/// - Teclado numérico custom (sem autocomplete do SO)
/// - PIN mascarado com dots
/// - Shake animation em erro
/// - Suporta PINs de 3-6 dígitos (tamanho variável do ERP)
/// - Botão ✓ no keypad para confirmar (em vez de auto-submit fixo)
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import '../../../core/config/app_config_service.dart';
import '../../../core/session/session_service.dart';
import '../../../core/sync/sync_service.dart';
import '../../../core/network/auto_sync_service.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_typography.dart';
import '../home/main_navigation_scaffold.dart';
import '../setup/setup_screen.dart';
import 'branch_selection_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final SessionService _session = GetIt.I<SessionService>();
  final SyncService    _sync    = GetIt.I<SyncService>();

  static const int _minPinLength     = 3;
  static const int _maxPinLength     = 6;
  static const int _maxAttempts     = 3;
  static const int _lockoutSeconds  = 30;

  // ── Estado ────────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _sellers = [];
  String? _selectedSellerId;
  String  _selectedSellerName = '';
  String  _pin       = '';
  bool    _loading   = false;
  bool    _syncing   = false;
  String? _errorMsg;
  String? _serverUrl;
  String? _apiKey;
  String  _activeBranchName = '';
  int     _failedAttempts  = 0;
  int     _lockoutRemaining = 0;  // segundos restantes de bloqueio
  Timer?  _lockoutTimer;
  late AnimationController _shakeController;
  late Animation<double>   _shakeAnimation;
  bool    _hasSellersButBlockedByCompany = false;

  bool get _isLockedOut => _lockoutRemaining > 0;

  // ── Fases da tela ────────────────────────────────────────────────────────
  bool get _isSelectingSeller => _selectedSellerId == null;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticOut),
    );
    _loadSellers();
  }

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    _shakeController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Throttle — bloqueia 30s após 3 tentativas erradas
  // ─────────────────────────────────────────────────────────────────────────────

  void _startLockout() {
    _lockoutTimer?.cancel();
    setState(() => _lockoutRemaining = _lockoutSeconds);
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        _lockoutRemaining--;
        if (_lockoutRemaining <= 0) {
          t.cancel();
          _failedAttempts = 0;
          _errorMsg = null;
        }
      });
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Carregamento de vendedores
  // ─────────────────────────────────────────────────────────────────────────

  /// Busca vendedores locais. Se vazio ou forceSync, tenta sincronizar com o middleware.
  Future<void> _loadSellers({bool forceSync = false}) async {
    setState(() => _loading = true);
    try {
      final config = GetIt.I<AppConfigService>();
      final serverUrl = await config.getServerUrl();
      final apiKey = await config.getApiKey();
      final branchName = await config.getBranchName() ?? '';
      final activeBranchEmpresaId = await config.getBranchErpEmpresaId();
      
      if (mounted) {
        setState(() {
          _serverUrl = serverUrl;
          _apiKey = apiKey;
          _activeBranchName = branchName;
        });
      }

      var unfilteredList = forceSync ? <Map<String, dynamic>>[] : await _session.getLocalSellers();
      if (unfilteredList.isEmpty) {
        // Primeira vez (ou resync forçado): sincroniza com o servidor
        setState(() { _loading = false; _syncing = true; });
        await _sync.pullSellers();
        unfilteredList = await _session.getLocalSellers();
        setState(() => _syncing = false);
      }

      var list = List<Map<String, dynamic>>.from(unfilteredList);
      if (activeBranchEmpresaId != null) {
        list = list.where((s) {
          final empId = s['erp_empresa_id'] as int?;
          return empId == null || empId == activeBranchEmpresaId;
        }).toList();
      }

      final hasSellersButBlockedByCompany = unfilteredList.isNotEmpty && list.isEmpty;

      setState(() {
        _sellers = list;
        _hasSellersButBlockedByCompany = hasSellersButBlockedByCompany;
        // Se só há um vendedor, pré-seleciona automaticamente
        if (_sellers.length == 1) {
          _selectedSellerId   = _sellers.first['id'].toString();
          _selectedSellerName = _sellers.first['name'] as String? ?? '';
        }
        _loading = false;
      });
    } catch (e) {
      debugPrint('[LoginScreen] _loadSellers error: $e');
      setState(() {
        _loading = false;
        _syncing = false;
        _errorMsg = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PIN
  // ─────────────────────────────────────────────────────────────────────────

  void _onDigit(String digit) {
    if (_loading || _isLockedOut || _pin.length >= _maxPinLength) return;
    HapticFeedback.lightImpact();
    setState(() { _pin += digit; _errorMsg = null; });
  }

  void _onDelete() {
    if (_loading || _isLockedOut || _pin.isEmpty) return;
    HapticFeedback.lightImpact();
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _submit() async {
    if (_loading || _isLockedOut || _selectedSellerId == null) return;
    setState(() { _loading = true; _errorMsg = null; });

    try {
      await _session.loginWithERP(
        sellerId: _selectedSellerId!,
        pin:      _pin,
      );
      if (!mounted) return;

      // O sincronismo completo agora é executado silenciosamente em segundo plano, liberando a tela principal imediatamente.

      // Dispara a sincronização automática em background logo após o login
      try {
        GetIt.I<AutoSyncService>().triggerManual();
      } catch (e) {
        debugPrint('[LoginScreen] Erro ao disparar sincronização automática pós-login: $e');
      }

      Navigator.of(context).pushReplacementNamed('/home');
    } on AuthException catch (e) {
      _failedAttempts++;
      HapticFeedback.mediumImpact();
      final remaining = _maxAttempts - _failedAttempts;
      String msg = e.message;
      if (_failedAttempts >= _maxAttempts) {
        _startLockout();
        msg = 'PIN incorreto. Aguarde $_lockoutSeconds segundos.';
      } else if (remaining == 1) {
        msg = '${e.message} (mais 1 tentativa antes do bloqueio)';
      }
      setState(() { _errorMsg = msg; _pin = ''; _loading = false; });
      _shakeController.forward(from: 0);
    } catch (e) {
      setState(() { _errorMsg = 'Erro: $e'; _pin = ''; _loading = false; });
      _shakeController.forward(from: 0);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // UI
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: SafeArea(
        child: _loading && _sellers.isEmpty
            ? _buildLoadingState()
            : _isSelectingSeller
                ? _buildSellerList()
                : _buildPinScreen(),
      ),
    );
  }

  // ── Loading ───────────────────────────────────────────────────────────────

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            _syncing ? 'Sincronizando vendedores...' : 'Carregando...',
            style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  // ── Lista de vendedores ───────────────────────────────────────────────────

  Widget _buildSellerList() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 40),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Coliseu App', style: AppTypography.headlineLarge.copyWith(
                      color: AppColors.primary, fontWeight: FontWeight.w800,
                    )),
                    const SizedBox(height: 4),
                    Text('Selecione seu usuário', style: AppTypography.bodyLarge.copyWith(
                      color: AppColors.textSecondary,
                    )),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.settings_outlined, color: AppColors.textSecondary),
                tooltip: 'Configurações do servidor',
                onPressed: () async {
                  final changed = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(builder: (_) => const SetupScreen()),
                  );
                  if (changed == true) _loadSellers(forceSync: true);
                },
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildBranchCard(),
          if (_sellers.isEmpty)
            _buildNoSellersCard()
          else
            Expanded(
              child: ListView.separated(
                itemCount: _sellers.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _buildSellerTile(_sellers[i]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBranchCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary,
            AppColors.primary.withOpacity(0.85),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            // Navega para a BranchSelectionScreen
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const BranchSelectionScreen()),
            );
            // Ao retornar, recarrega os vendedores da nova filial
            _loadSellers(forceSync: true);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.storefront_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'FILIAL ATIVA',
                        style: AppTypography.bodySmall.copyWith(
                          color: Colors.white70,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _activeBranchName.isNotEmpty ? _activeBranchName : 'Toque para selecionar',
                        style: AppTypography.bodyLarge.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.swap_horiz_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSellerTile(Map<String, dynamic> seller) {
    final name    = seller['name'] as String? ?? '';
    final id      = seller['id'].toString();
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return Card(
      elevation: 0,
      color: AppColors.backgroundSecondary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        onTap: () => setState(() {
          _selectedSellerId   = id;
          _selectedSellerName = name;
          _pin                = '';
          _errorMsg           = null;
        }),
        leading: CircleAvatar(
          backgroundColor: AppColors.primary.withOpacity(0.15),
          child: Text(initial, style: const TextStyle(
            color: AppColors.primary, fontWeight: FontWeight.bold,
          )),
        ),
        title: Text(name, style: AppTypography.bodyLarge),
        trailing: const Icon(Icons.chevron_right, color: AppColors.textSecondary),
      ),
    );
  }

  Widget _buildNoSellersCard() {
    return Card(
      color: AppColors.backgroundSecondary,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            if (_syncing) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 12),
              Text('Sincronizando com o servidor...',
                textAlign: TextAlign.center,
                style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary)),
            ] else ...[
              const Icon(Icons.wifi_off, size: 40, color: AppColors.textSecondary),
              const SizedBox(height: 12),
              if (_errorMsg != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      Text(_errorMsg!,
                        textAlign: TextAlign.center,
                        style: AppTypography.bodyMedium.copyWith(color: Colors.red.shade700)),
                      if (_serverUrl != null && _apiKey != null) ...[
                        const SizedBox(height: 8),
                        Text('URL: $_serverUrl\nAPI Key: $_apiKey',
                          textAlign: TextAlign.center,
                          style: AppTypography.bodySmall.copyWith(color: Colors.red.shade900)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ] else
                Text(
                  _hasSellersButBlockedByCompany
                      ? 'Nenhum vendedor tem permissão de acesso a esta filial.\nContate o administrador.'
                      : 'Nenhum vendedor encontrado.\nConecte ao servidor para sincronizar.',
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
                ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _loadSellers(forceSync: true),
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar novamente'),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () async {
                  final changed = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(builder: (_) => const SetupScreen()),
                  );
                  if (changed == true) _loadSellers(forceSync: true);
                },
                icon: const Icon(Icons.settings_outlined, size: 18),
                label: const Text('Configurar Servidor / API Key'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Tela de PIN ───────────────────────────────────────────────────────────

  Widget _buildPinScreen() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          // Back button stays fixed at top
          const SizedBox(height: 16),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios),
                onPressed: () {
                  _lockoutTimer?.cancel();
                  setState(() {
                    _selectedSellerId  = null;
                    _pin               = '';
                    _errorMsg          = null;
                    _failedAttempts    = 0;
                    _lockoutRemaining  = 0;
                  });
                },
              ),
            ],
          ),
          // Scrollable content
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
          // Avatar e nome do vendedor
          CircleAvatar(
            radius: 36,
            backgroundColor: AppColors.primary.withOpacity(0.15),
            child: Text(
              _selectedSellerName.isNotEmpty ? _selectedSellerName[0].toUpperCase() : '?',
              style: AppTypography.headlineLarge.copyWith(color: AppColors.primary),
            ),
          ),
          const SizedBox(height: 12),
          Text(_selectedSellerName,
            style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('Digite seu PIN', style: AppTypography.bodyMedium.copyWith(
            color: AppColors.textSecondary)),
          const SizedBox(height: 20),
          // Dots do PIN com shake
          AnimatedBuilder(
            animation: _shakeAnimation,
            builder: (_, child) => Transform.translate(
              offset: Offset(_errorMsg != null ? ((_shakeAnimation.value - 0.5) * 20) : 0, 0),
              child: child,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_maxPinLength, (i) => Container(
                margin: const EdgeInsets.symmetric(horizontal: 8),
                width: 16, height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < _pin.length
                      ? (_errorMsg != null ? AppColors.error : AppColors.primary)
                      : i < _minPinLength
                          ? AppColors.textSecondary.withOpacity(0.3)
                          : AppColors.textSecondary.withOpacity(0.12),
                ),
              )),
            ),
          ),
          if (_isLockedOut) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_clock, size: 16, color: AppColors.error),
                  const SizedBox(width: 8),
                  Text(
                    'Bloqueado por $_lockoutRemaining s',
                    style: AppTypography.bodySmall.copyWith(color: AppColors.error, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ] else if (_errorMsg != null) ...[
            const SizedBox(height: 12),
            Text(_errorMsg!, style: AppTypography.bodySmall.copyWith(color: AppColors.error)),
          ],
          const SizedBox(height: 8),
          // Teclado numérico
          _buildNumericKeypad(),
          const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNumericKeypad() {
    final keys = [
      ['1','2','3'],
      ['4','5','6'],
      ['7','8','9'],
      ['','0','⌫'],
    ];
    final bool canSubmit = _pin.length >= _minPinLength && !_loading && !_isLockedOut;
    return Column(
      children: [
        ...keys.map((row) => Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: row.map((k) {
            if (k.isEmpty) return const SizedBox(width: 72, height: 72);
            return SizedBox(
              width: 72, height: 72,
              child: TextButton(
                onPressed: (_loading || _isLockedOut) ? null : () => k == '⌫' ? _onDelete() : _onDigit(k),
                style: TextButton.styleFrom(
                  shape: const CircleBorder(),
                  backgroundColor: AppColors.backgroundSecondary,
                ),
                child: k == '⌫'
                    ? const Icon(Icons.backspace_outlined, color: AppColors.textSecondary)
                    : Text(k, style: AppTypography.headlineMedium.copyWith(
                        color: AppColors.textPrimary, fontWeight: FontWeight.w500)),
              ),
            );
          }).toList(),
        )),
        const SizedBox(height: 16),
        // Botão Confirmar
        SizedBox(
          width: 200,
          height: 48,
          child: ElevatedButton(
            onPressed: canSubmit ? _submit : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppColors.textSecondary.withOpacity(0.2),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            ),
            child: _loading
                ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Entrar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }
}

/// branch_selection_screen.dart — Tela de seleção de filial com suporte offline
library;

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:get_it/get_it.dart';
import '../../core/config/app_config_service.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_typography.dart';
import '../../core/database/database_helper.dart';
import '../../core/session/session_service.dart';

// ── Model ──────────────────────────────────────────────────────────────────────

class BranchItem {
  final String id;
  final String name;
  final String? cnpj;
  final int erpEmpresaId;
  final int erpDeptoPadrao;
  final bool isDefault;

  const BranchItem({
    required this.id,
    required this.name,
    this.cnpj,
    required this.erpEmpresaId,
    required this.erpDeptoPadrao,
    this.isDefault = false,
  });

  factory BranchItem.fromJson(Map<String, dynamic> json) {
    return BranchItem(
      id:           json['id']           as String,
      name:         json['name']         as String,
      cnpj:         json['cnpj']         as String?,
      erpEmpresaId: (json['erpEmpresaId'] ?? 1) as int,
      erpDeptoPadrao: (json['erpDeptoPadrao'] ?? 1) as int,
      isDefault:    (json['isDefault']   ?? false) as bool,
    );
  }
}

// ── Screen ─────────────────────────────────────────────────────────────────────

class BranchSelectionScreen extends StatefulWidget {
  static const routeName = '/branch-selection';

  const BranchSelectionScreen({super.key});

  @override
  State<BranchSelectionScreen> createState() => _BranchSelectionScreenState();
}

class _BranchSelectionScreenState extends State<BranchSelectionScreen> with SingleTickerProviderStateMixin {
  final _config = AppConfigService();

  List<BranchItem> _branches = [];
  BranchItem?      _selected;
  bool             _isLoading = true;
  bool             _isConfirming = false;
  bool             _isOfflineMode = false;
  String?          _errorMsg;
  String?          _vendedorName;

  late AnimationController _animController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnimation = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    
    _loadInitialData();
  }
  
  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    // Tenta carregar o nome do vendedor logado para uma saudação personalizada
    final sessionData = await _config.getRefreshToken(); // O session service injeta sellerId
    // Para simplificar, colocaremos uma saudação genérica se não conseguirmos extrair.
    _vendedorName = 'Vendedor';
    await _loadBranches();
  }

  // ── Data fetching ────────────────────────────────────────────────────────────

  Future<void> _loadBranches() async {
    setState(() { _isLoading = true; _errorMsg = null; _isOfflineMode = false; });
    try {
      final serverUrl  = await _config.getServerUrl();
      final token      = await _config.getAccessToken();
      final dio = Dio(BaseOptions(
        baseUrl: serverUrl ?? '',
        connectTimeout: const Duration(seconds: 4),
        receiveTimeout: const Duration(seconds: 4),
        headers: {
          if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
      ));

      final response = await dio.get('/api/branches');
      final list = (response.data['branches'] as List<dynamic>? ?? [])
          .map((e) => BranchItem.fromJson(e as Map<String, dynamic>))
          .toList();

      if (!mounted) return;

      // Rule: NÃO mais auto-navegar se tiver só 1 filial! Sempre exibir.
      final defaultBranch = list.where((b) => b.isDefault).firstOrNull ?? list.firstOrNull;

      setState(() {
        _branches = list;
        _selected = defaultBranch;
        _isLoading = false;
      });
      _animController.forward();
    } on DioException catch (e) {
      if (!mounted) return;
      _handleOfflineFallback();
    } catch (e) {
      if (!mounted) return;
      _handleOfflineFallback();
    }
  }

  Future<void> _handleOfflineFallback() async {
    // ── Prevenção Offline (Resiliência) ──
    final cachedId = await _config.getBranchId();
    final cachedName = await _config.getBranchName() ?? 'Filial Local';
    
    if (cachedId != null && cachedId.isNotEmpty) {
      setState(() {
        _isLoading = false;
        _isOfflineMode = true;
        _selected = BranchItem(
          id: cachedId, 
          name: cachedName, 
          erpEmpresaId: 1, 
          erpDeptoPadrao: 1
        );
        _branches = [_selected!];
      });
      _animController.forward();
    } else {
      setState(() {
        _isLoading = false;
        _errorMsg = 'Você está offline e não possui nenhuma filial salva na sessão. Conecte-se à internet para carregar.';
      });
      _animController.forward();
    }
  }

  Future<void> _persistAndNavigate(BranchItem branch) async {
    final currentBranchId = await _config.getBranchId();
    
    if (currentBranchId != branch.id) {
      // 1. Verifica se há pedidos pendentes de sincronização (Opção A)
      final pendingItems = await DatabaseHelper().getSyncQueue('pending');
      if (pendingItems.isNotEmpty) {
        if (!mounted) return;
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Troca Bloqueada'),
            content: const Text(
              'Existem pedidos locais pendentes de envio/sincronização neste dispositivo.\n\n'
              'Por favor, sincronize ou envie todos os pedidos antes de trocar de filial.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Entendi'),
              ),
            ],
          ),
        );
        return;
      }

      // 2. Se for diferente e sem pendências, faz logout e wipe
      final session = GetIt.I<SessionService>();
      await session.logout();
      await DatabaseHelper().clearAllTables();
      
      // 3. Persiste a nova filial
      await _config.setBranch(
        branchId: branch.id, 
        branchName: branch.name,
        erpDeptoPadrao: branch.erpDeptoPadrao,
        erpEmpresaId: branch.erpEmpresaId,
      );

      if (!mounted) return;
      // 4. Reinicia a navegação do aplicativo para a tela de autenticação /auth-gate
      Navigator.of(context).pushNamedAndRemoveUntil('/auth-gate', (route) => false);
    } else {
      if (!mounted) return;
      final session = GetIt.I<SessionService>();
      if (session.isLoggedIn) {
        Navigator.of(context).pushReplacementNamed('/home');
      } else {
        Navigator.of(context).pushNamedAndRemoveUntil('/auth-gate', (route) => false);
      }
    }
  }

  Future<void> _handleConfirm() async {
    final branch = _selected;
    if (branch == null) return;

    setState(() => _isConfirming = true);
    try {
      await _persistAndNavigate(branch);
    } finally {
      if (mounted) setState(() => _isConfirming = false);
    }
  }

  // ── UI UX PRO MAX ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: Stack(
        children: [
          // Background Gradient Muted
          Positioned(
            top: -100,
            right: -50,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withOpacity(0.05),
              ),
            ),
          ),
          SafeArea(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Header Saudação ──────────────────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.storefront_rounded, size: 36, color: AppColors.primary),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Bem-vindo de volta!',
                      style: AppTypography.headingLarge.copyWith(color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Selecione a empresa/filial que você irá operar agora.',
                      style: AppTypography.bodyLarge.copyWith(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 24),

                    // ── Modo Offline Alert ──────────────────────────────────────────
                    if (_isOfflineMode)
                       Container(
                        margin: const EdgeInsets.only(bottom: 24),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.warningLight,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.warning.withOpacity(0.4)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.wifi_off_rounded, color: AppColors.warning),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Modo Offline: Usando a última filial logada.',
                                style: AppTypography.bodySmall.copyWith(
                                  color: AppColors.warningDM, fontWeight: FontWeight.bold
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // ── Content List ──────────────────────────────────────────────
                    Expanded(child: _buildContent()),

                    // ── Footer: Confirmar ─────────────────────────────────────────
                    if (!_isLoading && _branches.isNotEmpty)
                      _buildConfirmButton(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }

    if (_errorMsg != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.errorLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.cloud_off_rounded, size: 48, color: AppColors.error),
            ),
            const SizedBox(height: 20),
            Text(
              'Oops!',
              style: AppTypography.headingMedium.copyWith(color: AppColors.textPrimary),
            ),
            const SizedBox(height: 12),
            Text(
              _errorMsg!, 
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary)
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _loadBranches,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Tentar novamente', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
    }

    if (_branches.isEmpty) {
      return Center(
        child: Text(
          'Nenhuma filial cadastrada para você.\nContate o administrador.',
          textAlign: TextAlign.center,
          style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
        ),
      );
    }

    return ListView.separated(
      physics: const BouncingScrollPhysics(),
      itemCount: _branches.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final branch = _branches[index];
        final isSelected = _selected?.id == branch.id;

        return _BranchTilePremium(
          branch: branch,
          isSelected: isSelected,
          onTap: () => setState(() => _selected = branch),
        );
      },
    );
  }

  Widget _buildConfirmButton() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 16),
      child: FilledButton(
        onPressed: _selected != null && !_isConfirming ? _handleConfirm : null,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 2,
        ),
        child: _isConfirming
            ? const SizedBox(
                height: 24, width: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
              )
            : const Text(
                'Prosseguir para Vendas', 
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5)
              ),
      ),
    );
  }
}

// ── Branch Tile Premium ────────────────────────────────────────────────────────

class _BranchTilePremium extends StatelessWidget {
  final BranchItem branch;
  final bool isSelected;
  final VoidCallback onTap;

  const _BranchTilePremium({
    required this.branch,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: isSelected ? AppColors.primary.withOpacity(0.04) : AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected ? AppColors.primary : AppColors.border,
          width: isSelected ? 2 : 1,
        ),
        boxShadow: isSelected ? [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ] : [
          const BoxShadow(
            color: AppColors.elevation1,
            blurRadius: 4,
            offset: Offset(0, 2),
          )
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                // Identidade visual (ícone)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary : AppColors.surfaceMuted,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.apartment_rounded, 
                    color: isSelected ? Colors.white : AppColors.textTertiary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                
                // Informação
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              branch.name,
                              style: AppTypography.bodyLarge.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (branch.isDefault) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.warningLight,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'Padrão',
                                style: AppTypography.bodySmall.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.warningDM,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        branch.cnpj?.isNotEmpty == true ? 'CNPJ: ${branch.cnpj}' : 'Empresa ID: ${branch.erpEmpresaId}',
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Radio indicator customizado
                const SizedBox(width: 16),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? AppColors.primary : AppColors.border,
                      width: isSelected ? 6 : 2,
                    ),
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

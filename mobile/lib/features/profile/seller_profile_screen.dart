/// SellerProfileScreen — Tela de perfil do vendedor logado.
///
/// Exibe:
/// - Dados da sessão ativa (SellerSession): nome, empresa
/// - Dados extras do vendedor sincronizados: e-mail, desconto máx., comissão
/// - Status de última sincronização por entidade
/// - Ações: sync manual, limpar cache de dados (com confirmação)
///
/// Acessível via ícone de perfil no AppBar do MainNavigationScaffold.
library;

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_typography.dart';
import '../../../core/network/auto_sync_service.dart';
import '../../../core/session/session_service.dart';
import '../../../core/database/database_helper.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../settings/server_config_screen.dart';
import '../activation/activation_screen.dart';
import '../performance/seller_performance_screen.dart';
import '../auth/branch_selection_screen.dart';
import '../auth/login_screen.dart';

class SellerProfileScreen extends StatefulWidget {
  const SellerProfileScreen({super.key});

  @override
  State<SellerProfileScreen> createState() => _SellerProfileScreenState();
}

class _SellerProfileScreenState extends State<SellerProfileScreen> {
  final _session  = GetIt.I<SessionService>();
  final _autoSync = GetIt.I<AutoSyncService>();
  final _db       = GetIt.I<DatabaseHelper>();
  final _dateFmt  = DateFormat("dd/MM/yyyy 'às' HH:mm", 'pt_BR');

  bool _syncing = false;

  // Dados extras do vendedor (tabela sellers no SQLite)
  String?  _email;
  double?  _maxDiscount;
  double?  _commission;

  // Última sincronização por entidade
  Map<String, String?> _syncMeta = {};

  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadVersion();
    _autoSync.stateNotifier.addListener(_onSyncChanged);
  }

  @override
  void dispose() {
    _autoSync.stateNotifier.removeListener(_onSyncChanged);
    super.dispose();
  }

  void _onSyncChanged() {
    if (mounted) {
      _loadData();
    }
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() {
      _appVersion = '${info.version}+${info.buildNumber}';
    });
  }

  Future<void> _loadData() async {
    final session = _session.activeSession;
    if (session == null) return;

    final db      = await _db.database;

    // Busca extras do vendedor do cache local
    final rows = await db.query(
      'sellers',
      where:     'id = ?',
      whereArgs: [session.sellerId],
      limit: 1,
    );

    if (rows.isNotEmpty) {
      final row = rows.first;
      _email       = row['email'] as String?;
      _maxDiscount = (row['max_discount'] as num?)?.toDouble();
      _commission  = (row['commission'] as num?)?.toDouble();
    }

    // Datas de sincronização
    final catalog  = await _db.getSyncMetadata('last_catalog_sync');
    final sellers  = await _db.getSyncMetadata('last_sellers_sync');
    final payment  = await _db.getSyncMetadata('last_payment_species_sync');
    final natureza = await _db.getSyncMetadata('last_natureza_sync');
    final customers = await _db.getSyncMetadata('last_customers_sync');

    final conditions = await _db.getSyncMetadata('last_payment_conditions_sync');

    if (!mounted) return;
    setState(() {
      _syncMeta = {
        'Catálogo':              catalog,
        'Vendedores':            sellers,
        'Espécie de Pagamento':  payment,
        'Condição de Pagamento': conditions,
        'Natureza de Operação':  natureza,
        'Clientes':              customers,
      };
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Ações
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _triggerSync() async {
    setState(() => _syncing = true);
    await _autoSync.triggerManual();
    await _loadData();
    if (!mounted) return;
    setState(() => _syncing = false);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Sincronização concluída.'),
      backgroundColor: AppColors.syncSuccess,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _clearSyncCache() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Limpar cache de sync?'),
        content: const Text(
          'O catálogo, clientes e formas de pagamento serão baixados novamente '
          'na próxima sincronização.\n\n'
          'Pedidos pendentes NÃO serão afetados.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.syncError),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Limpar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;

    final db = await _db.database;
    await db.delete('products');
    await db.delete('customers');
    await db.delete('sellers');
    await db.delete('payment_species');
    await db.delete('payment_conditions');
    await db.delete('natureza_operacao');
    await db.delete('sync_metadata');

    setState(() {
      _email = null; _maxDiscount = null; _commission = null;
      _syncMeta = {};
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Cache limpo. Execute uma sincronização para baixar os dados novamente.'),
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Sair do aplicativo?'),
        content: const Text(
          'Você será desconectado e precisará fazer login novamente.\n\n'
          'Pedidos pendentes de sincronização podem ser perdidos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.syncError),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sair', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;
    await _session.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final session = _session.activeSession;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Perfil do Vendedor'),
      ),
      backgroundColor: AppColors.surfaceSecondary,
      body: session == null
          ? const Center(child: Text('Sem sessão ativa.'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Avatar + Nome ────────────────────────────────────────
                _buildAvatarSection(session.sellerName, session.companyName),
                const SizedBox(height: 16),

                // ── Dados do vendedor ────────────────────────────────────
                _buildSection('Dados do Vendedor', [
                  _infoRow(Icons.badge_outlined,     'Código',          session.sellerId),
                  _infoRow(Icons.person_outlined,     'Nome',            session.sellerName),
                  _infoRow(Icons.business_rounded,    'Empresa',         session.companyName),
                  _infoRow(Icons.email_outlined,      'E-mail',          _email ?? '—'),
                  _infoRow(Icons.percent_rounded,     'Desconto máx.',   _maxDiscount != null ? '${_maxDiscount!.toStringAsFixed(0)}%' : '—'),
                  _infoRow(Icons.attach_money_rounded,'Comissão',        _commission  != null ? '${_commission!.toStringAsFixed(1)}%'  : '—'),
                ]),
                const SizedBox(height: 16),

                // ── Última sincronização ──────────────────────────────────
                _buildSection('Última Sincronização', [
                  ..._syncMeta.entries.map((e) => _syncRow(e.key, e.value)),
                ]),
                const SizedBox(height: 24),

                // ── Ações ─────────────────────────────────────────────────
                ElevatedButton.icon(
                  onPressed: _syncing ? null : _triggerSync,
                  icon: _syncing
                      ? const SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.sync_rounded),
                  label: Text(_syncing ? 'Sincronizando…' : 'Sincronizar Agora'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _clearSyncCache,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.syncError),
                    foregroundColor: AppColors.syncError,
                  ),
                  icon: const Icon(Icons.delete_sweep_outlined),
                  label: const Text('Limpar Cache de Dados'),
                ),
                const SizedBox(height: 12),





                // Botão de troca de filial
                OutlinedButton.icon(
                  onPressed: () async {
                    // Verifica pendências no SQLite local
                    final pendingItems = await _db.getSyncQueue('pending');
                    if (!mounted) return;

                    if (pendingItems.isNotEmpty) {
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

                    // Se não tiver pendências, navega para a seleção de filiais
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const BranchSelectionScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.swap_horiz_rounded),
                  label: const Text('Trocar de Filial / Empresa'),
                ),
                // Botão Trocar Licença
                OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ActivationScreen(),
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.primary),
                    foregroundColor: AppColors.primary,
                  ),
                  icon: const Icon(Icons.vpn_key_rounded),
                  label: const Text('Trocar Licença'),
                ),
                const SizedBox(height: 24),

                // Botão Sair
                OutlinedButton.icon(
                  onPressed: () => _confirmLogout(),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.syncError),
                    foregroundColor: AppColors.syncError,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Sair'),
                ),
                const SizedBox(height: 32),
                Center(
                  child: Text(
                    'Versão do App: $_appVersion',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  Widget _buildAvatarSection(String name, String company) {
    final initials = name.trim().split(' ')
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();

    return Center(
      child: Column(
        children: [
          CircleAvatar(
            radius: 36,
            backgroundColor: AppColors.actionPrimary,
            child: Text(
              initials,
              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 10),
          Text(name, style: AppTypography.cardTitle),
          const SizedBox(height: 4),
          Text(company, style: AppTypography.body.copyWith(color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> rows) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfacePrimary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Text(title, style: AppTypography.fieldLabel.copyWith(color: AppColors.textSecondary)),
          ),
          const Divider(height: 1, color: AppColors.divider),
          ...rows,
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.textSecondary),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: AppTypography.body.copyWith(color: AppColors.textSecondary))),
          Text(value, style: AppTypography.bodyBold),
        ],
      ),
    );
  }

  Widget _syncRow(String label, String? isoDate) {
    String display;
    if (isoDate == null) {
      display = 'Nunca';
    } else {
      try {
        display = _dateFmt.format(DateTime.parse(isoDate).toLocal());
      } catch (_) {
        display = isoDate;
      }
    }

    final isNever = isoDate == null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(
            isNever ? Icons.warning_amber_rounded : Icons.check_circle_outline_rounded,
            size: 18,
            color: isNever ? AppColors.syncError : AppColors.syncSuccess,
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: AppTypography.body.copyWith(color: AppColors.textSecondary))),
          Text(
            display,
            style: AppTypography.badge.copyWith(
              color: isNever ? AppColors.syncError : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// SyncQueueScreen — Fila de sincronização com visão por entidade + pedidos.
///
/// Layout redesign:
/// - Seção "Visão Geral" com cards por entidade (Catálogo, Clientes, Pedidos)
/// - Cada card mostra: ícone, nome, última sync, qtd itens, badge de status
/// - Seção "Pedidos" com status individual e expansão de erros
/// - Botão "Forçar sync completa" no topo
/// - Pull-to-refresh recarrega tudo
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:coliseu_speed/core/config/app_config_service.dart';
import 'package:intl/intl.dart';
import '../../core/database/database_helper.dart';
import '../../core/repositories/models/models.dart';
import '../../core/repositories/order_repository.dart';
import '../../core/session/session_service.dart';
import '../../core/sync/sync_service.dart';
import '../../core/network/auto_sync_service.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_typography.dart';

class SyncQueueScreen extends StatefulWidget {
  const SyncQueueScreen({super.key});

  @override
  State<SyncQueueScreen> createState() => _SyncQueueScreenState();
}

class _SyncQueueScreenState extends State<SyncQueueScreen> with WidgetsBindingObserver {
  final OrderRepository _repo    = GetIt.I<OrderRepository>();
  final SyncService     _sync    = GetIt.I<SyncService>();
  final DatabaseHelper  _db      = GetIt.I<DatabaseHelper>();
  final AutoSyncService _autoSync = GetIt.I<AutoSyncService>();
  final _currencyFmt = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
  final _dateFmt     = DateFormat('dd/MM/yy HH:mm', 'pt_BR');
  final _dateFmtShort = DateFormat('dd/MM HH:mm', 'pt_BR');

  List<Order> _orders   = [];
  bool _loading         = false;
  bool _syncing         = false;
  final Set<String> _expandedErrors = {};

  // Entity overview data
  int _productCount  = 0;
  int _customerCount = 0;
  String? _lastCatalogSync;
  String? _lastCustomersSync;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAll();
    _autoSync.stateNotifier.addListener(_onSyncChanged);
  }

  @override
  void dispose() {
    _autoSync.stateNotifier.removeListener(_onSyncChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onSyncChanged() {
    if (_autoSync.stateNotifier.value == AutoSyncState.success) {
      _loadAll();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    final config = GetIt.I<AppConfigService>();
    final companyId = await config.getBranchId() ?? GetIt.I<SessionService>().activeSession?.companyId ?? '1';
    final results = await Future.wait([
      _repo.getAll(companyId: companyId),
      _db.getSyncMetadata('last_catalog_sync'),
      _db.getSyncMetadata('last_customers_sync'),
      _countProducts(),
      _countCustomers(),
    ]);
    if (!mounted) return;
    setState(() {
      _orders           = results[0] as List<Order>;
      _lastCatalogSync  = results[1] as String?;
      _lastCustomersSync = results[2] as String?;
      _productCount     = results[3] as int;
      _customerCount    = results[4] as int;
      _loading          = false;
    });
  }

  Future<int> _countProducts() async {
    final db = await _db.database;
    final r = await db.rawQuery('SELECT COUNT(*) AS c FROM products');
    return (r.first['c'] as num?)?.toInt() ?? 0;
  }

  Future<int> _countCustomers() async {
    final db = await _db.database;
    final r = await db.rawQuery('SELECT COUNT(*) AS c FROM customers');
    return (r.first['c'] as num?)?.toInt() ?? 0;
  }

  Future<void> _fullSync() async {
    setState(() => _syncing = true);
    try {
      await _sync.syncPendingOrders();
      await _sync.pullCatalog();
    } finally {
      if (mounted) {
        setState(() => _syncing = false);
        await _loadAll();
      }
    }
  }

  Future<void> _retryOrder(Order order) async {
    await _sync.syncPendingOrders();
    await _loadAll();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final errorOrders   = _orders.where((o) => o.hasError).toList();
    final syncingOrders = _orders.where((o) => o.syncStatus == OrderSyncStatus.syncing).toList();
    final pendingOrders = _orders.where((o) => o.isPending).toList();
    final syncedOrders  = _orders.where((o) => o.isSynced).toList();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.surfaceDM : AppColors.surfaceSecondary,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAll,
              child: CustomScrollView(
                slivers: [
                  // ── Alerta de Pedidos Não Sincronizados ──────────────
                  if (pendingOrders.isNotEmpty || errorOrders.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Container(
                        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.warning.withOpacity(0.4)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 24),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Atenção: Você possui pedidos que ainda não foram sincronizados. Não limpe o cache do aplicativo nem o desinstale para evitar a perda desses dados.',
                                style: AppTypography.body.copyWith(
                                  color: isDark ? Colors.orange[200] : Colors.orange[900],
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // ── Visão Geral das Entidades ────────────────────────
                  SliverToBoxAdapter(child: _buildEntityOverview(isDark, errorOrders, pendingOrders)),

                  // ── Ações em lote ────────────────────────────────────
                  if (errorOrders.isNotEmpty || pendingOrders.isNotEmpty)
                    SliverToBoxAdapter(child: _buildBatchActions(errorOrders, pendingOrders)),

                  // ── Seção: Sincronizando ─────────────────────────────
                  if (syncingOrders.isNotEmpty) ...[
                    _sectionHeader('🔄  Sincronizando (${syncingOrders.length})', AppColors.syncInProgress),
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (_, i) => _OrderTile(
                          order:    syncingOrders[i],
                          currency: _currencyFmt,
                          dateFmt:  _dateFmt,
                        ),
                        childCount: syncingOrders.length,
                      ),
                    ),
                  ],

                  // ── Seção: Erros ─────────────────────────────────────
                  if (errorOrders.isNotEmpty) ...[
                    _sectionHeader('⚠️  Com falha (${errorOrders.length})', AppColors.syncError),
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (_, i) => _OrderTile(
                          order:       errorOrders[i],
                          currency:    _currencyFmt,
                          dateFmt:     _dateFmt,
                          isExpanded:  _expandedErrors.contains(errorOrders[i].id),
                          onToggle:    () => setState(() {
                            final id = errorOrders[i].id;
                            _expandedErrors.contains(id)
                                ? _expandedErrors.remove(id)
                                : _expandedErrors.add(id);
                          }),
                          onRetry: () => _retryOrder(errorOrders[i]),
                        ),
                        childCount: errorOrders.length,
                      ),
                    ),
                  ],

                  // ── Seção: Aguardando ────────────────────────────────
                  if (pendingOrders.isNotEmpty) ...[
                    _sectionHeader('⏳  Aguardando (${pendingOrders.length})', AppColors.syncPending),
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (_, i) => _OrderTile(
                          order:    pendingOrders[i],
                          currency: _currencyFmt,
                          dateFmt:  _dateFmt,
                        ),
                        childCount: pendingOrders.length,
                      ),
                    ),
                  ],

                  // ── Seção: Confirmados ───────────────────────────────
                  if (syncedOrders.isNotEmpty) ...[
                    _sectionHeader('✅  Confirmados (${syncedOrders.length})', AppColors.syncSuccess),
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (_, i) => _OrderTile(
                          order:    syncedOrders[i],
                          currency: _currencyFmt,
                          dateFmt:  _dateFmt,
                        ),
                        childCount: syncedOrders.length,
                      ),
                    ),
                  ],

                  // ── Estado vazio ─────────────────────────────────────
                  if (_orders.isEmpty)
                    SliverFillRemaining(child: _emptyState()),

                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              ),
            ),
    );
  }

  // ── Entity Overview Section ──────────────────────────────────────────────

  Widget _buildEntityOverview(bool isDark, List<Order> errors, List<Order> pending) {
    final pendingOrderCount = errors.length + pending.length;
    final syncedOrderCount  = _orders.where((o) => o.isSynced).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header + sync button
          Row(
            children: [
              Text('Visão Geral', style: AppTypography.headingMedium),
              const Spacer(),
              _syncing
                  ? const SizedBox(
                      width: 24, height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : FilledButton.icon(
                      onPressed: _fullSync,
                      icon: const Icon(Icons.sync_rounded, size: 16),
                      label: const Text('Sincronizar Tudo'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                    ),
            ],
          ),
          const SizedBox(height: 12),

          // Entity cards grid
          Row(
            children: [
              Expanded(child: _entityCard(
                icon: Icons.inventory_2_outlined,
                label: 'Catálogo',
                count: '$_productCount produtos',
                lastSync: _lastCatalogSync,
                color: AppColors.primary,
                isDark: isDark,
              )),
              const SizedBox(width: 10),
              Expanded(child: _entityCard(
                icon: Icons.people_outline_rounded,
                label: 'Clientes',
                count: '$_customerCount clientes',
                lastSync: _lastCustomersSync,
                color: AppColors.info,
                isDark: isDark,
              )),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _entityCard(
                icon: Icons.receipt_long_outlined,
                label: 'Pedidos',
                count: pendingOrderCount > 0
                    ? '$pendingOrderCount pendente${pendingOrderCount > 1 ? 's' : ''}'
                    : '$syncedOrderCount sincronizado${syncedOrderCount != 1 ? 's' : ''}',
                lastSync: null,
                color: pendingOrderCount > 0 ? AppColors.warning : AppColors.success,
                isDark: isDark,
                badge: pendingOrderCount > 0
                    ? _badgeChip('$pendingOrderCount', AppColors.warning)
                    : null,
              )),
              const SizedBox(width: 10),
              Expanded(child: _entityCard(
                icon: Icons.error_outline_rounded,
                label: 'Erros',
                count: errors.isEmpty
                    ? 'Nenhum erro'
                    : '${errors.length} pedido${errors.length > 1 ? 's' : ''}',
                lastSync: null,
                color: errors.isEmpty ? AppColors.success : AppColors.error,
                isDark: isDark,
                badge: errors.isNotEmpty
                    ? _badgeChip('${errors.length}', AppColors.error)
                    : null,
              )),
            ],
          ),
        ],
      ),
    );
  }

  Widget _entityCard({
    required IconData icon,
    required String label,
    required String count,
    required String? lastSync,
    required Color color,
    required bool isDark,
    Widget? badge,
  }) {
    final syncDate = lastSync != null ? DateTime.tryParse(lastSync) : null;
    final isNeverSynced = syncDate != null &&
        syncDate.year < 2000;
    final syncLabel = isNeverSynced || syncDate == null
        ? 'Nunca sincronizado'
        : 'Sync: ${_dateFmtShort.format(syncDate)}';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceElevatedDM : AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.15)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: color),
              ),
              const Spacer(),
              if (badge != null) badge,
            ],
          ),
          const SizedBox(height: 8),
          Text(label, style: AppTypography.bodyBold.copyWith(fontSize: 13)),
          const SizedBox(height: 2),
          Text(count, style: AppTypography.caption.copyWith(
            color: AppColors.textSecondary, fontSize: 11)),
          if (lastSync != null) ...[
            const SizedBox(height: 2),
            Text(syncLabel, style: AppTypography.badge.copyWith(
              color: isNeverSynced ? AppColors.warning : AppColors.textTertiary,
              fontSize: 9,
            )),
          ],
        ],
      ),
    );
  }

  Widget _badgeChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text, style: AppTypography.badge.copyWith(
        color: color, fontSize: 10, fontWeight: FontWeight.w700)),
    );
  }

  // ── Batch Actions ────────────────────────────────────────────────────────

  Widget _buildBatchActions(List<Order> errors, List<Order> pending) {
    final total = errors.length + pending.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$total ${total == 1 ? 'pedido aguarda' : 'pedidos aguardam'} sync',
              style: AppTypography.body.copyWith(color: AppColors.textSecondary),
            ),
          ),
          _syncing
              ? const SizedBox(
                  width: 24, height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : FilledButton.tonal(
                  onPressed: _fullSync,
                  child: const Text('Retentar todos'),
                ),
        ],
      ),
    );
  }

  SliverToBoxAdapter _sectionHeader(String label, Color color) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(
          label,
          style: AppTypography.fieldLabel.copyWith(color: color),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_done_outlined, size: 64, color: AppColors.textTertiary),
          const SizedBox(height: 16),
          Text('Tudo sincronizado!',
            style: AppTypography.cardTitle.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Text('Nenhum pedido pendente.',
            style: AppTypography.body.copyWith(color: AppColors.textTertiary)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _OrderTile — Tile de pedido na lista de sync
// ─────────────────────────────────────────────────────────────────────────────

class _OrderTile extends StatefulWidget {
  final Order order;
  final NumberFormat currency;
  final DateFormat dateFmt;
  final bool isExpanded;
  final VoidCallback? onToggle;
  final VoidCallback? onRetry;

  const _OrderTile({
    required this.order,
    required this.currency,
    required this.dateFmt,
    this.isExpanded = false,
    this.onToggle,
    this.onRetry,
  });

  @override
  State<_OrderTile> createState() => _OrderTileState();
}

class _OrderTileState extends State<_OrderTile> with SingleTickerProviderStateMixin {
  late final AnimationController _rotationCtrl;

  @override
  void initState() {
    super.initState();
    _rotationCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (widget.order.syncStatus == OrderSyncStatus.syncing) {
      _rotationCtrl.repeat();
    }
  }

  @override
  void didUpdateWidget(_OrderTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.order.syncStatus == OrderSyncStatus.syncing) {
      if (!_rotationCtrl.isAnimating) _rotationCtrl.repeat();
    } else {
      _rotationCtrl.stop();
      _rotationCtrl.reset();
    }
  }

  @override
  void dispose() {
    _rotationCtrl.dispose();
    super.dispose();
  }

  Color get _statusColor => switch (widget.order.syncStatus) {
    OrderSyncStatus.error   => AppColors.syncError,
    OrderSyncStatus.pending => AppColors.syncPending,
    OrderSyncStatus.syncing => AppColors.syncInProgress,
    OrderSyncStatus.synced  => AppColors.syncSuccess,
    OrderSyncStatus.draft   => AppColors.textTertiary,
  };

  IconData get _statusIcon => switch (widget.order.syncStatus) {
    OrderSyncStatus.error   => Icons.warning_rounded,
    OrderSyncStatus.pending => Icons.schedule_rounded,
    OrderSyncStatus.syncing => Icons.sync_rounded,
    OrderSyncStatus.synced  => Icons.check_circle_rounded,
    OrderSyncStatus.draft   => Icons.edit_note_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final order = widget.order;

    final card = Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfacePrimary,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          // Linha principal
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            onTap: widget.onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  // Ícone animado no estado syncing
                  order.syncStatus == OrderSyncStatus.syncing
                      ? RotationTransition(
                          turns: _rotationCtrl,
                          child: Icon(_statusIcon, color: _statusColor, size: 22),
                        )
                      : Icon(_statusIcon, color: _statusColor, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(order.customerName, style: AppTypography.bodyBold, maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(
                          widget.dateFmt.format(DateTime.tryParse(order.createdAt) ?? DateTime.now()),
                          style: AppTypography.badge.copyWith(color: AppColors.textSecondary),
                        ),
                        if (order.hasError && order.retryCount > 0)
                          Text(
                            '${order.retryCount} ${order.retryCount == 1 ? 'tentativa' : 'tentativas'}',
                            style: AppTypography.badge.copyWith(color: AppColors.syncPending),
                          ),
                        if (order.isSynced)
                          Text(
                            order.erpOrderId != null
                                ? 'Pedido ERP #${order.erpOrderId}'
                                : 'Aguardando nº ERP...',
                            style: AppTypography.badge.copyWith(
                              color: order.erpOrderId != null ? AppColors.syncSuccess : AppColors.textTertiary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(widget.currency.format(order.totalAmount), style: AppTypography.priceNormal),
                      Text(order.syncStatus.label, style: AppTypography.badge.copyWith(color: _statusColor)),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Detalhe de erro expandível
          if (order.hasError && widget.isExpanded)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              decoration: const BoxDecoration(
                color: AppColors.syncErrorLight,
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(8)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(color: AppColors.syncError, height: 1),
                  const SizedBox(height: 8),
                  Text(
                    'Detalhes do erro:',
                    style: AppTypography.badge.copyWith(color: AppColors.syncError),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    order.errorMessage?.isNotEmpty == true
                        ? order.errorMessage!
                        : 'Falha ao comunicar com o servidor. Verifique a conexão e tente novamente.',
                    style: AppTypography.body.copyWith(color: AppColors.syncError, fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Retentar este pedido'),
                      onPressed: widget.onRetry,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.syncError,
                        side: const BorderSide(color: AppColors.syncError),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );

    // Swipe-to-retry: apenas pedidos com erro e callback disponível
    if (!order.hasError || widget.onRetry == null) return card;

    return Dismissible(
      key: ValueKey('retry-${order.id}'),
      direction: DismissDirection.startToEnd,
      confirmDismiss: (_) async {
        widget.onRetry!();
        return false;
      },
      background: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.syncError,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        child: const Row(
          children: [
            Icon(Icons.refresh_rounded, color: Colors.white, size: 22),
            SizedBox(width: 8),
            Text('Retry', style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
          ],
        ),
      ),
      child: card,
    );
  }
}

/// OrderHistoryScreen — Histórico de pedidos com filtro de período e totalizadores.
///
/// UX:
/// - Chips de período rápido: Hoje / 7 dias / 30 dias / Tudo
/// - Seletor de data customizado (DatePicker) para de/até
/// - Campo de busca por nome do cliente
/// - Lista agrupada por dia com totalizador por dia
/// - Tile expansível: itens do pedido, status badge, n° ERP, natureza
/// - Rodapé fixo com: total de pedidos, valor bruto, desconto e líquido
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:coliseu_sales/core/config/app_config_service.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/cart/cart_notifier.dart';
import '../../core/network/auto_sync_service.dart';
import '../../core/session/session_service.dart';
import '../../core/repositories/models/models.dart';
import '../../core/repositories/order_repository.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_typography.dart';
import '../../core/services/order_pdf_service.dart';
import '../new_order/new_order_screen.dart';
import '../../shared/order_share_sheet.dart';
import 'order_detail_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Enum de período rápido
// ─────────────────────────────────────────────────────────────────────────────

enum _PeriodPreset { today, month, all }

extension _PeriodPresetExt on _PeriodPreset {
  String get label => switch (this) {
    _PeriodPreset.today => 'Hoje',
    _PeriodPreset.month => '30 dias',
    _PeriodPreset.all   => 'Tudo',
  };

  /// Retorna a data de início para este preset (null = sem limite).
  DateTime? get fromDate {
    final now = DateTime.now();
    return switch (this) {
      _PeriodPreset.today => DateTime(now.year, now.month, now.day),
      _PeriodPreset.month => now.subtract(const Duration(days: 30)),
      _PeriodPreset.all   => null,
    };
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// OrderHistoryScreen
// ─────────────────────────────────────────────────────────────────────────────

class OrderHistoryScreen extends StatefulWidget {
  final CartNotifier cart;

  const OrderHistoryScreen({super.key, required this.cart});

  @override
  State<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends State<OrderHistoryScreen> {
  final OrderRepository   _repo      = GetIt.I<OrderRepository>();
  final AutoSyncService   _autoSync  = GetIt.I<AutoSyncService>();
  final _currencyFmt = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final _dateFmt     = DateFormat('dd/MM/yy HH:mm', 'pt_BR');
  final _dayFmt      = DateFormat('EEEE, dd/MM/yyyy', 'pt_BR');

  // ── Estado de filtro ──────────────────────────────────────────────────────
  _PeriodPreset   _preset       = _PeriodPreset.month;
  DateTime?       _customFrom;
  DateTime?       _customTo;
  String          _search       = '';
  Timer?          _debounce;
  bool            _onlyQuotes   = false;

  // ── Dados ─────────────────────────────────────────────────────────────────
  List<Order>     _orders       = [];
  bool            _loading      = false;
  final Set<String> _expanded   = {};

  // ── Formatadores auxiliares ───────────────────────────────────────────────
  DateTime? get _effectiveFrom =>
      _preset == _PeriodPreset.all && _customFrom == null
          ? null
          : _customFrom ?? _preset.fromDate;

  DateTime? get _effectiveTo => _customTo;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Carregamento
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() => _loading = true);
    final config = GetIt.I<AppConfigService>();
    final companyId = await config.getBranchId() ?? GetIt.I<SessionService>().activeSession?.companyId ?? '1';
    final orders = await _repo.getHistory(
      companyId: companyId,
      from:   _effectiveFrom,
      to:     _effectiveTo,
      search: _search.isEmpty ? null : _search,
    );
    if (!mounted) return;
    setState(() {
      _orders  = orders;
      _loading = false;
    });
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      setState(() => _search = value);
      _load();
    });
  }

  void _selectPreset(_PeriodPreset preset) {
    setState(() {
      _preset     = preset;
      _customFrom = null;
      _customTo   = null;
    });
    _load();
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context:        context,
      firstDate:      DateTime(now.year - 2),
      lastDate:       now,
      initialDateRange: _customFrom != null && _customTo != null
          ? DateTimeRange(start: _customFrom!, end: _customTo!)
          : DateTimeRange(
              start: now.subtract(const Duration(days: 30)),
              end:   now,
            ),
      locale:         const Locale('pt', 'BR'),
      helpText:       'Selecione o período',
      cancelText:     'Cancelar',
      confirmText:    'Aplicar',
      builder:        (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: AppColors.actionPrimary),
        ),
        child: child!,
      ),
    );

    if (range == null || !mounted) return;
    setState(() {
      _customFrom = range.start;
      _customTo   = range.end;
      _preset     = _PeriodPreset.all; // nenhum chip selecionado
    });
    _load();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Agrupamento por dia
  // ─────────────────────────────────────────────────────────────────────────

  /// Agrupa os pedidos por data (yyyy-MM-dd) preservando a ordem decrescente.
  Map<String, List<Order>> _groupByDay(List<Order> orders) {
    final map = <String, List<Order>>{};
    for (final o in orders) {
      final dt  = DateTime.tryParse(o.createdAt) ?? DateTime.now();
      final key = '${dt.year}-${dt.month.toString().padLeft(2,'0')}-${dt.day.toString().padLeft(2,'0')}';
      map.putIfAbsent(key, () => []).add(o);
    }
    return map;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Totalizadores
  // ─────────────────────────────────────────────────────────────────────────

  double _calculateTotalGross(List<Order> list) {
    if (_onlyQuotes) {
      return list.fold(0.0, (s, o) => s + o.totalAmount + o.discountValue);
    }
    return list.where((o) => !o.isDraft).fold(0.0, (s, o) => s + o.totalAmount + o.discountValue);
  }

  double _calculateTotalDiscount(List<Order> list) {
    if (_onlyQuotes) {
      return list.fold(0.0, (s, o) => s + o.discountValue);
    }
    return list.where((o) => !o.isDraft).fold(0.0, (s, o) => s + o.discountValue);
  }

  double _calculateTotalNet(List<Order> list) {
    if (_onlyQuotes) {
      return list.fold(0.0, (s, o) => s + o.totalAmount);
    }
    return list.where((o) => !o.isDraft).fold(0.0, (s, o) => s + o.totalAmount);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _openNewOrder() async {
    // Limpa o carrinho antes de criar novo pedido
    widget.cart.clear();
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => NewOrderScreen(cart: widget.cart),
      ),
    );
    if (result == true && mounted) {
      _load(); // Refresh list after saving
    }
  }

  Future<void> _cloneOrder(Order order) async {
    // Mostra diálogo de carregamento
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const PopScope(
        canPop: false,
        child: Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(20.0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(width: 16),
                  Text('Clonando pedido...'),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    try {
      final result = await widget.cart.cloneFromOrder(order);
      
      // Fecha o diálogo de carregamento
      if (mounted) Navigator.pop(context);
      
      if (!mounted) return;

      // Exibe alertas se houver itens sem estoque ou descontinuados
      if (result.hasWarnings) {
        final messages = <String>[];
        if (result.outOfStockProducts.isNotEmpty) {
          messages.add(
            'Itens sem estoque (incluídos no pedido):\n· ${result.outOfStockProducts.join('\n· ')}'
          );
        }
        if (result.missingProducts.isNotEmpty) {
          messages.add(
            'Itens descontinuados do catálogo (NÃO incluídos):\n· ${result.missingProducts.join('\n· ')}'
          );
        }

        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Aviso de Clonagem'),
            content: Text(messages.join('\n\n')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }

      if (!mounted) return;
      
      // Abre a tela de novo pedido com o carrinho preenchido
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => NewOrderScreen(cart: widget.cart),
        ),
      );
      _load();
    } catch (e) {
      if (mounted) Navigator.pop(context); // fecha carregador
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao clonar pedido: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayedOrders = _onlyQuotes
        ? _orders.where((o) => o.isDraft).toList()
        : _orders;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pedidos'),
        automaticallyImplyLeading: false,
        actions: [
          ValueListenableBuilder<AutoSyncState>(
            valueListenable: _autoSync.stateNotifier,
            builder: (_, state, __) {
              final isSyncing = state == AutoSyncState.syncing;
              final color = switch (state) {
                AutoSyncState.syncing => AppColors.primary,
                AutoSyncState.success => AppColors.success,
                AutoSyncState.partial => AppColors.warning,
                AutoSyncState.idle    => AppColors.textSecondary,
              };
              return IconButton(
                tooltip: isSyncing ? 'Sincronizando...' : 'Sincronizar pedidos',
                icon: AnimatedRotation(
                  turns: isSyncing ? 1 : 0,
                  duration: const Duration(seconds: 1),
                  child: Icon(Icons.sync_rounded, color: color),
                ),
                onPressed: isSyncing ? null : () => _autoSync.triggerManual(),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Cabeçalho de filtros ───────────────────────────────────────────
          _buildFilters(),

          // ── Lista / empty state ───────────────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : displayedOrders.isEmpty
                    ? _buildEmpty()
                    : _buildList(displayedOrders),
          ),

          // ── Rodapé totalizador ─────────────────────────────────────────────
          if (!_loading && displayedOrders.isNotEmpty) _buildFooter(displayedOrders),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'new_order_fab',
        onPressed: _openNewOrder,
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Seção de filtros
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildFilters() {
    final hasCustomRange = _customFrom != null && _customTo != null;
    final customLabel    = hasCustomRange
        ? '${DateFormat('dd/MM', 'pt_BR').format(_customFrom!)} → ${DateFormat('dd/MM', 'pt_BR').format(_customTo!)}'
        : 'Período';

    return Container(
      color: AppColors.surfacePrimary,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Chips de período ──────────────────────────────────────────────
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // Chip de Orçamentos
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    avatar: Icon(
                      Icons.receipt_long_outlined,
                      size: 16,
                      color: _onlyQuotes ? const Color(0xFF7C4DFF) : AppColors.textSecondary,
                    ),
                    label: const Text('Orçamentos'),
                    selected: _onlyQuotes,
                    onSelected: (selected) {
                      setState(() {
                        _onlyQuotes = selected;
                      });
                    },
                    selectedColor: const Color(0xFF7C4DFF).withOpacity(0.12),
                    checkmarkColor: const Color(0xFF7C4DFF),
                    labelStyle: AppTypography.badge.copyWith(
                      color: _onlyQuotes
                          ? const Color(0xFF7C4DFF)
                          : AppColors.textSecondary,
                      fontWeight: _onlyQuotes ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
                // Separador sutil
                Container(
                  width: 1,
                  height: 24,
                  color: AppColors.border,
                  margin: const EdgeInsets.only(right: 6),
                ),

                // Chips rápidos
                ..._PeriodPreset.values.map((p) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label:           Text(p.label),
                    selected:        _preset == p && !hasCustomRange,
                    onSelected:      (_) => _selectPreset(p),
                    selectedColor:   AppColors.syncInProgressLight,
                    checkmarkColor:  AppColors.actionPrimary,
                    labelStyle: AppTypography.badge.copyWith(
                      color: (_preset == p && !hasCustomRange)
                          ? AppColors.actionPrimary
                          : AppColors.textSecondary,
                    ),
                  ),
                )),

                // Chip de período customizado
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    avatar:          const Icon(Icons.date_range_rounded, size: 16),
                    label:           Text(customLabel),
                    selected:        hasCustomRange,
                    onSelected:      (_) => _pickCustomRange(),
                    selectedColor:   AppColors.syncInProgressLight,
                    checkmarkColor:  AppColors.actionPrimary,
                    labelStyle: AppTypography.badge.copyWith(
                      color: hasCustomRange
                          ? AppColors.actionPrimary
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 6),

          // ── Campo de busca ────────────────────────────────────────────────
          TextField(
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              hintText:       'Buscar por cliente...',
              hintStyle:      AppTypography.body.copyWith(color: AppColors.textTertiary),
              prefixIcon:     const Icon(Icons.search_rounded, size: 20),
              isDense:        true,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
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
                borderSide:   const BorderSide(color: AppColors.actionPrimary, width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Lista agrupada por dia
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildList(List<Order> displayedOrders) {
    final grouped = _groupByDay(displayedOrders);
    final days    = grouped.keys.toList(); // já em ordem decrescente (insert order)

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 8),
        itemCount: days.length,
        itemBuilder: (_, i) {
          final dayKey    = days[i];
          final dayOrders = grouped[dayKey]!;
          final dayTotal  = dayOrders.fold(0.0, (s, o) => s + o.totalAmount);
          final dayDt     = DateTime.parse(dayKey);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Cabeçalho do dia ──────────────────────────────────────
              Container(
                color: AppColors.surfaceSecondary,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _dayFmt.format(dayDt).replaceFirstMapped(
                          RegExp(r'^\w'),
                          (m) => m.group(0)!.toUpperCase(),
                        ),
                        style: AppTypography.fieldLabel.copyWith(color: AppColors.textSecondary),
                      ),
                    ),
                    // Totalizador diário
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _currencyFmt.format(dayTotal),
                          style: AppTypography.bodyBold.copyWith(color: AppColors.actionPrimary),
                        ),
                        Text(
                          _onlyQuotes
                              ? '${dayOrders.length} ${dayOrders.length == 1 ? 'orçamento' : 'orçamentos'}'
                              : '${dayOrders.length} ${dayOrders.length == 1 ? 'pedido' : 'pedidos'}',
                          style: AppTypography.badge.copyWith(color: AppColors.textTertiary),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // ── Tiles do dia ──────────────────────────────────────────
              ...dayOrders.map((o) => _OrderHistoryTile(
                order:      o,
                currency:   _currencyFmt,
                dateFmt:    _dateFmt,
                isExpanded: _expanded.contains(o.id),
                onTap:      () => setState(() {
                  _expanded.contains(o.id)
                      ? _expanded.remove(o.id)
                      : _expanded.add(o.id);
                }),
                onShare:    () => _shareOrder(o),
                onClone:    () => _cloneOrder(o),
                onDetail:   () async {
                  if (o.isDraft) {
                    // Orçamento → abre para edição
                    await widget.cart.loadFromOrder(o);
                    if (!mounted) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => NewOrderScreen(cart: widget.cart),
                      ),
                    ).then((_) => _load());
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => OrderDetailScreen(
                          order: o,
                          cart:  widget.cart,
                        ),
                      ),
                    ).then((_) => _load());
                  }
                },
              )),
            ],
          );
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Estado vazio
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.receipt_long_outlined, size: 64, color: AppColors.textTertiary),
          const SizedBox(height: 16),
          Text(
            _onlyQuotes ? 'Nenhum orçamento encontrado' : 'Nenhum pedido encontrado',
            style: AppTypography.cardTitle.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Text(
            _onlyQuotes
                ? 'Não há orçamentos neste período.'
                : 'Tente alterar o filtro de período ou a busca.',
            style: AppTypography.body.copyWith(color: AppColors.textTertiary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Rodapé totalizador
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildFooter(List<Order> displayedOrders) {
    final count = displayedOrders.length;
    final totalGross = _calculateTotalGross(displayedOrders);
    final totalDiscount = _calculateTotalDiscount(displayedOrders);
    final totalNet = _calculateTotalNet(displayedOrders);

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surfacePrimary,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 72, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _onlyQuotes
                      ? '$count ${count == 1 ? 'orçamento' : 'orçamentos'} no período'
                      : '$count ${count == 1 ? 'pedido' : 'pedidos'} no período',
                  style: AppTypography.body.copyWith(color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Totalizador em grid 3 colunas
          Row(
            children: [
              _totalizerCell('Bruto',    totalGross,    AppColors.textSecondary),
              _totalizerDivider(),
              _totalizerCell('Desconto', totalDiscount, AppColors.syncError),
              _totalizerDivider(),
              _totalizerCell('Líquido',  totalNet,      AppColors.syncSuccess),
            ],
          ),
        ],
      ),
    );
  }

  Widget _totalizerCell(String label, double value, Color valueColor) => Expanded(
    child: Column(
      children: [
        Text(label, style: AppTypography.badge.copyWith(color: AppColors.textTertiary)),
        const SizedBox(height: 2),
        Text(
          _currencyFmt.format(value),
          style: AppTypography.bodyBold.copyWith(color: valueColor, fontSize: 13),
        ),
      ],
    ),
  );

  Widget _totalizerDivider() => Container(
    width: 1, height: 32,
    color: AppColors.border,
    margin: const EdgeInsets.symmetric(horizontal: 4),
  );

  // ─────────────────────────────────────────────────────────────────────────
  // Share de pedido (#7)
  // ─────────────────────────────────────────────────────────────────────────

  /// Mostra opções de compartilhamento usando o componente central.
  void _shareOrder(Order order) {
    OrderShareSheet.show(context, order);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _OrderHistoryTile — tile expansível por pedido
// ─────────────────────────────────────────────────────────────────────────────

class _OrderHistoryTile extends StatelessWidget {

  final Order          order;
  final NumberFormat   currency;
  final DateFormat     dateFmt;
  final bool           isExpanded;
  final VoidCallback   onTap;

  /// Callback para share de pedido (#7).
  final VoidCallback   onShare;

  /// Callback para abrir tela de detalhes.
  final VoidCallback   onDetail;

  /// Callback para clonar o pedido.
  final VoidCallback   onClone;

  const _OrderHistoryTile({
    required this.order,
    required this.currency,
    required this.dateFmt,
    required this.isExpanded,
    required this.onTap,
    required this.onShare,
    required this.onDetail,
    required this.onClone,
  });

  Color get _statusColor => switch (order.syncStatus) {
    OrderSyncStatus.synced  => AppColors.syncSuccess,
    OrderSyncStatus.pending => AppColors.syncPending,
    OrderSyncStatus.syncing => AppColors.syncInProgress,
    OrderSyncStatus.error   => AppColors.syncError,
    OrderSyncStatus.draft   => const Color(0xFF7C4DFF),
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      decoration: BoxDecoration(
        color: AppColors.surfacePrimary,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          // ── Linha principal ───────────────────────────────────────────
          InkWell(
            borderRadius: BorderRadius.vertical(
              top:    const Radius.circular(8),
              bottom: isExpanded ? Radius.zero : const Radius.circular(8),
            ),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Row 1: Status dot + Customer name + Total ────────
                  Row(
                    children: [
                      Container(
                        width: 8, height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _statusColor,
                        ),
                      ),
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                order.customerName,
                                style: AppTypography.bodyBold,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (order.isDraft) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF7C4DFF).withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: const Color(0xFF7C4DFF).withOpacity(0.3), width: 0.5),
                                ),
                                child: const Text(
                                  'ORÇAMENTO',
                                  style: TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF7C4DFF),
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(currency.format(order.totalAmount), style: AppTypography.priceNormal),
                    ],
                  ),
                  const SizedBox(height: 4),

                  // ── Row 2: Date + Payment info ──────────────────────
                  Padding(
                    padding: const EdgeInsets.only(left: 18),
                    child: Row(
                      children: [
                        Text(
                          dateFmt.format(
                            DateTime.tryParse(order.createdAt) ?? DateTime.now(),
                          ),
                          style: AppTypography.badge.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        if (order.paymentSpeciesName != null) ...[
                          Text(' · ', style: AppTypography.badge.copyWith(
                            color: AppColors.textTertiary,
                          )),
                          Flexible(
                            child: Text(
                              '${order.paymentSpeciesName}${order.paymentConditionName != null ? ' (${order.paymentConditionName})' : ''}',
                              style: AppTypography.badge.copyWith(
                                color: AppColors.textSecondary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // ── Row 3: Natureza + ERP + discount + actions ──────
                  Padding(
                    padding: const EdgeInsets.only(left: 18),
                    child: Row(
                      children: [
                        Expanded(
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 2,
                            children: [
                              if (order.naturezaDescricao != null)
                                Text(
                                  order.naturezaDescricao!,
                                  style: AppTypography.badge.copyWith(
                                    color: AppColors.textTertiary, fontSize: 10,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              if (order.erpOrderId != null)
                                Text(
                                  'ERP #${order.erpOrderId}',
                                  style: AppTypography.badge.copyWith(
                                    color: AppColors.syncSuccess, fontSize: 10,
                                  ),
                                ),
                              if (order.syncStatus == OrderSyncStatus.error && order.errorMessage != null && order.errorMessage!.isNotEmpty)
                                Text(
                                  order.errorMessage!,
                                  style: AppTypography.badge.copyWith(
                                    color: AppColors.syncError, fontSize: 10,
                                  ),
                                ),
                              if (order.discountValue > 0)
                                Text(
                                  '-${currency.format(order.discountValue)}',
                                  style: AppTypography.badge.copyWith(color: AppColors.syncError, fontSize: 10),
                                ),
                            ],
                          ),
                        ),
                        // Action icons
                        IconButton(
                          icon: const Icon(Icons.open_in_new_rounded, size: 17),
                          color: AppColors.actionPrimary,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                          tooltip: 'Ver detalhes',
                          onPressed: onDetail,
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy_rounded, size: 16),
                          color: AppColors.actionPrimary,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                          tooltip: 'Repetir pedido (Clonar)',
                          onPressed: onClone,
                        ),
                        IconButton(
                          icon: const Icon(Icons.share_outlined, size: 16),
                          color: AppColors.textSecondary,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                          tooltip: 'Compartilhar pedido',
                          onPressed: onShare,
                        ),
                        Icon(
                          isExpanded
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          color: AppColors.textTertiary,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Itens expandidos ──────────────────────────────────────────
          if (isExpanded)
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: AppColors.surfaceSecondary,
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(8)),
              ),
              child: Column(
                children: [
                  const Divider(height: 1, color: AppColors.border),
                  ...order.items.map((item) => Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.productName, style: AppTypography.body, maxLines: 1, overflow: TextOverflow.ellipsis),
                              Text(
                                '${item.quantity.toStringAsFixed(item.quantity == item.quantity.truncate() ? 0 : 1)} × ${currency.format(item.unitPrice)}',
                                style: AppTypography.badge.copyWith(color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        Text(currency.format(item.totalPrice), style: AppTypography.badge),
                      ],
                    ),
                  )),
                  const SizedBox(height: 10),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

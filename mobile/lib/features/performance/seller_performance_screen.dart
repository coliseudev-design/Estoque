/// SellerPerformanceScreen — Cockpit de vendas completo do vendedor.
///
/// Exibe métricas calculadas a partir dos pedidos sincronizados no SQLite:
/// - KPIs com comparativo vs período anterior (↑↓)
/// - Gráfico de evolução de faturamento (line chart)
/// - Comissão estimada
/// - Análise de margem / rentabilidade
/// - Análise de descontos concedidos
/// - Saúde da carteira de clientes (ativos, inativos, perdidos, novos)
/// - Distribuição geográfica por cidade
/// - Mix de produtos por categoria e marca
/// - Top produtos e clientes
///
/// Filtros de período: 30 dias, Tudo, Personalizado.
library;

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';
import '../../core/database/database_helper.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_typography.dart';
import '../../core/repositories/order_repository.dart';
import '../../core/repositories/performance_repository.dart';
import '../../core/session/session_service.dart';
import '../../core/config/app_config_service.dart';
import '../../core/sync/sync_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Period filter
// ─────────────────────────────────────────────────────────────────────────────

enum _Period { today, week, month, all }

extension on _Period {
  String get label => switch (this) {
    _Period.today => 'Hoje',
    _Period.week  => '7 dias',
    _Period.month => '30 dias',
    _Period.all   => 'Tudo',
  };

  DateTime? get from {
    final now = DateTime.now();
    return switch (this) {
      _Period.today => DateTime(now.year, now.month, now.day),
      _Period.week  => now.subtract(const Duration(days: 7)),
      _Period.month => now.subtract(const Duration(days: 29)),
      _Period.all   => null,
    };
  }

  /// Retorna o início do período anterior equivalente (para comparação).
  DateTime? get prevFrom {
    final now = DateTime.now();
    return switch (this) {
      _Period.today => DateTime(now.year, now.month, now.day - 1),
      _Period.week  => now.subtract(const Duration(days: 13)),
      _Period.month => now.subtract(const Duration(days: 59)),
      _Period.all   => null,
    };
  }

  DateTime? get prevTo {
    final f = from;
    if (f == null) return null;
    return f.subtract(const Duration(seconds: 1));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

class SellerPerformanceScreen extends StatefulWidget {
  const SellerPerformanceScreen({super.key});

  @override
  State<SellerPerformanceScreen> createState() => _SellerPerformanceScreenState();
}

class _SellerPerformanceScreenState extends State<SellerPerformanceScreen> {
  final _repo     = GetIt.I<OrderRepository>();
  final _session  = GetIt.I<SessionService>();
  final _db       = GetIt.I<DatabaseHelper>();
  final _perfRepo = GetIt.I<PerformanceRepository>();

  _Period       _period     = _Period.month;
  DateTime?     _customFrom;
  DateTime?     _customTo;
  bool          _loading    = true;

  // ── KPIs do período atual ─────────────────────────────────────────────────
  int           _ordersCount = 0;
  double        _total      = 0;
  double        _avgTicket  = 0;
  double        _commission = 0;
  double?       _commissionRate;
  SellerKpis?   _erpKpis;  // KPIs reais do ERP (MINHASVENDAS)
  SalesRankings? _rankings; // Rankings de vendas do ERP (L_VENDAS_*)

  // ── KPIs do período anterior (para comparação) ────────────────────────────
  double        _prevTotal     = 0;
  int           _prevCount     = 0;
  double        _prevAvgTicket = 0;

  // ── Faturamento por dia (para line chart) ──────────────────────────────────
  Map<String, double> _revenueByDay = {};
  Map<String, int>    _ordersByDay  = {};

  // ── Top clientes e produtos ────────────────────────────────────────────────
  List<MapEntry<String, double>> _topCustomers = [];
  List<Map<String, dynamic>>     _topProducts  = [];

  // ── Margem e descontos ─────────────────────────────────────────────────────
  double _grossRevenue    = 0;
  double _estimatedCost   = 0;
  double _totalDiscount   = 0;
  int    _ordersWithDisc  = 0;
  int    _ordersHighDisc  = 0; // > 10%

  // ── Carteira de clientes ───────────────────────────────────────────────────
  int _activeClients   = 0;
  int _inactiveClients = 0;
  int _lostClients     = 0;
  int _newClients      = 0;
  int _totalClients    = 0;

  // ── Distribuição geográfica ────────────────────────────────────────────────
  List<MapEntry<String, double>> _topCities = [];
  // fallback 30 dias (usado quando Hoje e SQLite vazio)
  List<MapEntry<String, double>> _topCitiesFallback = [];

  // ── Mix por categoria ──────────────────────────────────────────────────────
  List<MapEntry<String, double>> _categoryMix = [];

  // ── Heatmap de dias da semana (Mon=0..Sun=6) ───────────────────────────────
  List<int>    _weekdayOrders  = List.filled(7, 0);
  List<double> _weekdayRevenue = List.filled(7, 0.0);

  // ── Clientes inativos (45+ dias sem compra) ────────────────────────────────
  List<Map<String, dynamic>> _inactiveAlert = [];

  // ── Produtos recomendados (top lucrativos não vendidos no mês atual) ────────
  List<Map<String, dynamic>> _recommendedProducts = [];

  // ── Projeção de fechamento do mês (memoizado) ────────────────────────
  double _projectedTotal   = 0;
  double _projectedDailyAvg = 0;
  double _projectedRemaining = 0;
  double _projectedRatio   = 0;  // vs meta ERP (0..1.2)
  Color  _projectedColor   = AppColors.primary;

  // SUGGESTION FIX: Formatters como static final — instanciados 1x, nunca recriados.
  static final _cur     = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  static final _dateFmt = DateFormat('dd/MM', 'pt_BR');
  static final _monthFmt = DateFormat('MMMM/yyyy', 'pt_BR');
  static final _monthNameFmt = DateFormat('MMMM', 'pt_BR');

  @override
  void initState() {
    super.initState();
    _init();
  }

  /// Sequencia o carregamento: ERP primeiro (rankings + KPIs),
  /// depois dados de período que dependem dos rankings.
  Future<void> _init() async {
    await _loadErpData();  // popula _rankings e _erpKpis
    _loadData();           // usa _rankings para popular charts
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Data loading
  // ─────────────────────────────────────────────────────────────────────────

  /// Carrega dados do ERP que são independentes do filtro de período:
  /// taxa de comissão e KPIs mensais (MINHASVENDAS).
  ///
  /// Chamado uma única vez no [initState]. Rankings são carregados em [_loadData].
  Future<void> _loadErpData() async {
    try {
      final sellerId = _session.activeSession?.sellerId;
      if (sellerId == null) return;

      final db   = await _db.database;
      final rows = await db.query('sellers', columns: ['commission'],
          where: 'id = ?', whereArgs: [sellerId], limit: 1);
      if (rows.isNotEmpty) {
        _commissionRate = (rows.first['commission'] as num?)?.toDouble();
      }

      final config = GetIt.I<AppConfigService>();
      final sync   = GetIt.instance<SyncService>();

      // [VPS-FIRST] Sempre tenta pull do VPS quando online.
      // Garante que mesmo após reinstalação ou clear do SQLite os dados aparecem.
      // pullPerformanceAndReturn usa deptoId da resposta como chave SQLite e
      // armazena em SharedPreferences para uso offline.
      _erpKpis = await sync.pullPerformanceAndReturn(sellerId);

      // Se offline ou pull falhou, tenta ler do SQLite com cachedDeptoId.
      if (_erpKpis == null) {
        debugPrint('[Performance] VPS indisponível — lendo SQLite (offline fallback)');
        final cachedDeptoId = await config.getCachedDeptoId();
        final companyId     = cachedDeptoId.toString();
        _erpKpis = await _perfRepo.get(companyId, sellerId);
      }

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('[Performance] Erro em _loadErpData: $e');
    }
  }

  /// Mapeia o enum [_Period] para a string de API usada no Worker/Redis.
  String get _periodKey => _period.name; // today, week, month, all

  /// Formata DateTime para ISO yyyy-MM-dd (sem hora).
  String _isoDate(DateTime d) => '${d.year.toString().padLeft(4,'0')}-'
      '${d.month.toString().padLeft(2,'0')}-'
      '${d.day.toString().padLeft(2,'0')}';

  Future<void> _loadData() async {
    setState(() => _loading = true);

    try {
      if (_erpKpis != null) {
        _total = _period == _Period.today ? _erpKpis!.vendaDiaria : _erpKpis!.vendaMensal;
        _commission = _period == _Period.today ? _erpKpis!.comissaoDiaria : _erpKpis!.comissaoMensal;
        _ordersCount = _total > 0 ? 1 : 0;
      } else {
        _total = 0;
        _commission = 0;
        _ordersCount = 0;
      }

      _revenueByDay = {};
      _categoryMix = [];
      _weekdayRevenue = List.filled(7, 0.0);
      _weekdayOrders = List.filled(7, 0);
      _activeClients = 0;
      _inactiveClients = 0;
      _lostClients = 0;
      _topProducts = [];
      _topCustomers = [];
      _topCities = [];

      final sellerId = _session.activeSession?.sellerId;
      if (sellerId == null) return;

      final sync = GetIt.instance<SyncService>();
      final now = DateTime.now();
      final todayStr = _isoDate(now);

      if (_customFrom != null && _customTo != null) {
        // ── Período personalizado: consulta on-demand ao middleware ───────────
        final json = await sync.pullRankingsOnDemand(
          sellerId,
          dateFrom: _isoDate(_customFrom!),
          dateTo:   _isoDate(_customTo!),
        );
        _rankings = json != null ? _perfRepo.rankingsFromApiJson(json) : null;
      } else {
        // ── Períodos fixos: re-pull se o dado é de outro dia, não existe ou está vazio ───
        // [VPS-FIRST] Usa cachedDeptoId como chave SQLite (consistente com pullSalesRankings).
        final cachedDeptoId = await GetIt.I<AppConfigService>().getCachedDeptoId();
        final companyId     = cachedDeptoId.toString();
        final local = await _perfRepo.getRankings(companyId, sellerId, period: _periodKey);
        final isStale = local == null ||
            !local.syncedAt.startsWith(todayStr) || // dado de outro dia
            (local.topProducts.isEmpty && local.topClients.isEmpty && local.byRegion.isEmpty); // listas vazias

        if (isStale) {
          debugPrint('[Performance] rankings stale/empty para $_periodKey — re-pull');
          await sync.pullSalesRankings(sellerId, period: _periodKey);
        }
        _rankings = await _perfRepo.getRankings(companyId, sellerId, period: _periodKey);
      }

      if (_rankings != null && _rankings!.hasData) {
         for (final r in _rankings!.revenueByDay) {
            try {
               final d = DateTime.parse(r.date);
               final key = _dateFmt.format(d);
               _revenueByDay[key] = r.totalAmount;
            } catch (_) {}
         }

         _categoryMix = _rankings!.categoryMix.map((c) => MapEntry(c.name, c.total)).toList();

         for (final h in _rankings!.heatmapStats) {
             final idx = h.dayOfWeek >= 1 && h.dayOfWeek <= 7 ? h.dayOfWeek - 1 : 0;
             _weekdayRevenue[idx] = h.totalAmount;
             _weekdayOrders[idx] = h.totalAmount > 0 ? h.totalAmount.toInt() : 0;
         }

         _activeClients = _rankings!.clientHealth.actives;
         _inactiveClients = _rankings!.clientHealth.inactives;
         _lostClients = _rankings!.clientHealth.lost;

         _topProducts = _rankings!.topProducts.map((p) => {
             'product_code': p.productId.toString(),
             'product_name': p.name,
             'total_val': p.totalValue,
             'quantity': p.totalQty
         }).toList();

         _topCustomers = _rankings!.topClients.map((c) => MapEntry(c.name.isNotEmpty ? c.name : c.clientId.toString(), c.totalValue)).toList();
         _topCities = _rankings!.byRegion.map((r) => MapEntry(r.region, r.totalValue)).toList();

         // Total a partir dos rankings quando KPIs do ERP não cobrem o período
         if (_total == 0 && (_period == _Period.week || _period == _Period.all || _customFrom != null)) {
           _total = _rankings!.topClients.fold(0.0, (s, c) => s + c.totalValue);
         }
      }

      _calculateProjections();

    } catch (e) {
      debugPrint('[Performance] Erro geral em _loadData: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _calculateProjections() {
    final now = DateTime.now();
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final daysGone    = now.day.clamp(1, daysInMonth);
    _projectedDailyAvg  = _total / daysGone;
    _projectedTotal     = _projectedDailyAvg * daysInMonth;
    _projectedRemaining = (_projectedTotal - _total).clamp(0.0, double.infinity);

    final hasMeta  = _erpKpis != null && _erpKpis!.metaMensal > 0;
    final metaVal  = hasMeta ? _erpKpis!.metaMensal : 0.0;
    _projectedRatio = hasMeta ? (_projectedTotal / metaVal).clamp(0.0, 1.2) : 0.0;
    _projectedColor = hasMeta
        ? (_projectedRatio >= 1.0
            ? const Color(0xFF00B894)
            : _projectedRatio >= 0.7
                ? AppColors.warning
                : AppColors.error)
        : AppColors.primary;
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialDateRange: _customFrom != null && _customTo != null
          ? DateTimeRange(start: _customFrom!, end: _customTo!)
          : DateTimeRange(start: now.subtract(const Duration(days: 30)), end: now),
      locale: const Locale('pt', 'BR'),
      helpText: 'Selecione o período',
      cancelText: 'Cancelar',
      confirmText: 'Aplicar',
      builder: (ctx, child) => Theme(
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
    });
    _loadData();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Meu Desempenho'),
      ),
      body: Column(
        children: [
          _PeriodFilter(
            selected: _period,
            customFrom: _customFrom,
            customTo: _customTo,
            onPeriodChanged: (p) {
              setState(() {
                _period = p;
                _customFrom = _customTo = null;
              });
              _loadData();
            },
            onCustomTap: _pickCustomRange,
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _content(),
          ),
        ],
      ),
    );
  }

  Widget _content() {
    final hasErp = _erpKpis != null && _erpKpis!.hasData;

    // Se não tem dados do ERP, mostra mensagem de aguardo
    if (!hasErp && _ordersCount == 0) {
      return _erpWaitingState();
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        if (hasErp) ...[
          // ── Dados reais do ERP ────────────────────────────────────────
          _erpKpisCard(),
          const SizedBox(height: 16),
        ] else ...[
          // ERP não disponivel mas tem pedidos locais
          _erpWaitingBanner(),
          const SizedBox(height: 16),
        ],
        // ── Gráfico de Linha (Faturamento por Dia) ────────────────────
        _revenueChartSection(),
        const SizedBox(height: 16),
        // ── Gráfico comparativo (período atual vs anterior) ───────────
        _salesComparisonCard(),
        const SizedBox(height: 16),
        // ── 🎯 Projeção do fechamento do mês ─────────────────────────
        _monthProjectionCard(),
        const SizedBox(height: 16),
        // ── Saúde da Carteira ─────────────────────────────────────────
        _clientHealthCard(),
        const SizedBox(height: 16),
        // ── 📅 Heatmap de dias da semana ──────────────────────────────
        _weekdayHeatmapCard(),
        const SizedBox(height: 16),
        // ── Rankings: ERP se disponível, senão local ─────────────────
        _geographyCard(),
        const SizedBox(height: 16),
        _topProductsSection(),
        const SizedBox(height: 16),
        _topCustomersSection(),
      ],
    );
  }

  /// Banner informativo quando ERP data não esta disponível ainda.
  Widget _erpWaitingBanner() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF3E0),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFFFB74D)),
    ),
    child: Row(
      children: [
        const Icon(Icons.schedule_rounded, color: Color(0xFFF57C00), size: 24),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Aguardando sincronização dos dados do ERP...\n'
            'Os KPIs serão atualizados automaticamente.',
            style: AppTypography.body.copyWith(
                fontSize: 12, color: const Color(0xFFF57C00)),
          ),
        ),
      ],
    ),
  );

  /// Tela de aguardo quando não há nenhum dado (nem ERP nem local).
  Widget _erpWaitingState() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.cloud_sync_rounded, size: 64,
            color: AppColors.primary.withOpacity(0.4)),
        const SizedBox(height: 16),
        Text('Aguardando dados do ERP',
            style: AppTypography.bodyBold.copyWith(
                color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        Text(
            'Os dados de desempenho serão atualizados\n'
            'automaticamente após a sincronização do Worker.',
            textAlign: TextAlign.center,
            style: AppTypography.body.copyWith(
                color: AppColors.textTertiary, fontSize: 13)),
      ],
    ),
  );

  // ─────────────────────────────────────────────────────────────────────────
  // Gráfico comparativo — período atual vs período anterior
  // ─────────────────────────────────────────────────────────────────────────

  /// Gráfico de barras duplas: período atual (azul) vs período anterior (cinza).
  /// Quando disponível, inclui barra de meta do ERP (verde).
  Widget _salesComparisonCard() {
    // Fonte primária: ERP quando período bater (Hoje → vendaDiaria, 30 dias → vendaMensal).
    // Fallback: pedidos locais SQLite (app mobile).
    final erp = _erpKpis;
    final effectiveTotal = () {
      if (erp != null && erp.hasData && _customFrom == null) {
        if (_period == _Period.today  && erp.vendaDiaria  > 0) return erp.vendaDiaria;
        if (_period == _Period.month  && erp.vendaMensal  > 0) return erp.vendaMensal;
      }
      return _total;
    }();

    // Sem dados comparativos: período = Tudo ou sem pedidos
    final hasCurrent  = effectiveTotal > 0;
    final hasPrevious = _prevTotal > 0;
    final hasMeta     = erp != null && erp.metaMensal > 0;

    if (!hasCurrent && !hasPrevious) return const SizedBox.shrink();

    // Referência máxima para escalar as barras
    final metaVal = hasMeta ? erp!.metaMensal : 0.0;
    final maxVal  = [effectiveTotal, _prevTotal, metaVal]
        .fold(0.0, (m, v) => v > m ? v : m)
        .clamp(1.0, double.infinity);

    final delta = hasPrevious
        ? ((effectiveTotal - _prevTotal) / _prevTotal * 100)
        : null;
    final isUp  = delta != null && delta >= 0;

    const colorCurrent  = Color(0xFF0984E3); // azul  — período atual (ERP)
    const colorPrevious = Color(0xFFB2BEC3); // cinza — período anterior
    const colorMeta     = Color(0xFF00B894); // verde — meta ERP

    // Label da fonte do dado atual
    final erpLabel = erp != null && erp.hasData && _customFrom == null &&
        (_period == _Period.today || _period == _Period.month)
        ? '(ERP)' : '';

    return _card(
      title: '📊 Comparativo de Vendas',
      subtitle: _period == _Period.all ? null : _period.label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Delta badge
          if (delta != null)
            Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (isUp ? colorMeta : AppColors.error).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isUp ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                      size: 14,
                      color: isUp ? colorMeta : AppColors.error,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${isUp ? '+' : ''}${delta.toStringAsFixed(1)}% vs período anterior',
                      style: AppTypography.caption.copyWith(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isUp ? colorMeta : AppColors.error,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (delta != null) const SizedBox(height: 16),

          // ── Barra: Período atual (ERP) ────────────────────────────────
          _comparisonBar(
            label: 'Período atual $erpLabel'.trim(),
            value: effectiveTotal,
            ratio: effectiveTotal / maxVal,
            color: colorCurrent,
            isBold: true,
          ),
          const SizedBox(height: 10),

          // ── Barra: Período anterior ───────────────────────────────────
          if (hasPrevious)
            _comparisonBar(
              label: 'Período anterior',
              value: _prevTotal,
              ratio: _prevTotal / maxVal,
              color: colorPrevious,
              isBold: false,
            ),

          // ── Barra: Meta ERP ───────────────────────────────────────────
          if (hasMeta) ...[
            const SizedBox(height: 10),
            _comparisonBar(
              label: 'Meta mensal (ERP)',
              value: metaVal,
              ratio: metaVal / maxVal,
              color: colorMeta,
              isBold: false,
              isDashed: true,
            ),
          ],

          const SizedBox(height: 12),

          // ── Legenda ───────────────────────────────────────────────────
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              _legendDot(colorCurrent,  'Atual'),
              if (hasPrevious) _legendDot(colorPrevious, 'Anterior'),
              if (hasMeta)     _legendDot(colorMeta,     'Meta'),
            ],
          ),
        ],
      ),
    );
  }

  /// Uma linha de barra horizontal com label e valor monetário.
  Widget _comparisonBar({
    required String label,
    required double value,
    required double ratio,
    required Color color,
    required bool isBold,
    bool isDashed = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: AppTypography.caption.copyWith(
                    color: isBold ? AppColors.textPrimary : AppColors.textSecondary,
                    fontWeight: isBold ? FontWeight.w700 : FontWeight.normal,
                    fontSize: 11)),
            Text(_cur.format(value),
                style: AppTypography.caption.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 12)),
          ],
        ),
        const SizedBox(height: 4),
        LayoutBuilder(
          builder: (_, constraints) {
            final barWidth = constraints.maxWidth * ratio.clamp(0.0, 1.0);
            return Stack(
              children: [
                // Trilho de fundo
                Container(
                  height: isBold ? 14 : 10,
                  width: constraints.maxWidth,
                  decoration: BoxDecoration(
                    color: AppColors.border.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                // Barra preenchida
                AnimatedContainer(
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeOutCubic,
                  height: isBold ? 14 : 10,
                  width: barWidth,
                  decoration: BoxDecoration(
                    color: isDashed ? color.withOpacity(0.25) : color,
                    borderRadius: BorderRadius.circular(6),
                    border: isDashed
                        ? Border.all(color: color, width: 1.5)
                        : null,
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _legendDot(Color color, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 4),
      Text(label, style: AppTypography.caption.copyWith(
          color: AppColors.textTertiary, fontSize: 10)),
    ],
  );

  // ─────────────────────────────────────────────────────────────────────────
  // 🎯 Projeção do Mês
  // ─────────────────────────────────────────────────────────────────────────

  /// Projeta o fechamento do mês com base na média diária do período atual.
  /// Valores são memoizados em _calculate() para não recalcular a cada rebuild.
  Widget _monthProjectionCard() {
    if (_ordersCount == 0) return const SizedBox.shrink();

    final now          = DateTime.now();
    final daysInMonth  = DateTime(now.year, now.month + 1, 0).day;
    final daysGone     = now.day;
    final projected    = _projectedTotal;
    final dailyAvg     = _projectedDailyAvg;
    final remaining    = _projectedRemaining;
    final hasMeta      = _erpKpis != null && _erpKpis!.metaMensal > 0;
    final metaVal      = hasMeta ? _erpKpis!.metaMensal : 0.0;
    final projRatio    = _projectedRatio;
    final projColor    = _projectedColor;

    return _card(
      title: '🎯 Projeção de Fechamento',
      subtitle: _monthFmt.format(now),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Valor projetado destacado
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Projeção para ${_monthNameFmt.format(now)}',
                      style: AppTypography.caption.copyWith(
                          color: AppColors.textTertiary, fontSize: 10)),
                  const SizedBox(height: 2),
                  Text(_cur.format(projected),
                      style: AppTypography.headingLarge.copyWith(
                          color: projColor, fontSize: 22)),
                ],
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('Média/dia', style: TextStyle(
                      color: AppColors.textTertiary, fontSize: 10)),
                  Text(_cur.format(dailyAvg),
                      style: AppTypography.bodyBold.copyWith(
                          color: AppColors.textSecondary, fontSize: 13)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Barra de progresso do mês (dias transcorridos)
          Row(
            children: [
              Text('Dia $daysGone de $daysInMonth',
                  style: AppTypography.caption.copyWith(
                      color: AppColors.textTertiary, fontSize: 10)),
              const Spacer(),
              Text('${(daysGone / daysInMonth * 100).toStringAsFixed(0)}% do mês',
                  style: AppTypography.caption.copyWith(
                      color: AppColors.textTertiary, fontSize: 10)),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: daysGone / daysInMonth,
              minHeight: 6,
              backgroundColor: AppColors.border,
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF74B9FF)),
            ),
          ),
          // Barra de progresso vs meta (se disponível)
          if (hasMeta) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Text('Projeção vs Meta',
                    style: AppTypography.caption.copyWith(
                        color: AppColors.textTertiary, fontSize: 10)),
                const Spacer(),
                Text('${(projRatio * 100).toStringAsFixed(0)}% de ${_cur.format(metaVal)}',
                    style: AppTypography.caption.copyWith(
                        color: projColor, fontWeight: FontWeight.bold, fontSize: 10)),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: projRatio.clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: AppColors.border,
                valueColor: AlwaysStoppedAnimation<Color>(projColor),
              ),
            ),
          ],
          if (remaining > 0) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.07),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.trending_up_rounded,
                      size: 14, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Falta ${_cur.format(remaining)} para atingir a projeção de fechamento',
                      style: AppTypography.caption.copyWith(
                          color: AppColors.primary, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 📅 Heatmap de Dias da Semana
  // ─────────────────────────────────────────────────────────────────────────

  Widget _weekdayHeatmapCard() {
    if (_ordersCount == 0) return const SizedBox.shrink();
    final labels = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];
    final maxOrders = _weekdayOrders.fold(0, (m, v) => v > m ? v : m);
    final maxRev    = _weekdayRevenue.fold(0.0, (m, v) => v > m ? v : m);
    if (maxOrders == 0) return const SizedBox.shrink();

    const colorActive  = Color(0xFF0984E3);
    const colorWeekend = Color(0xFF6C5CE7);

    return _card(
      title: '📅 Seus Melhores Dias',
      subtitle: _period.label,
      child: Column(
        children: [
          // Barras verticais
          SizedBox(
            height: 90,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(7, (i) {
                final ratio = maxOrders > 0 ? _weekdayOrders[i] / maxOrders : 0.0;
                final isWeekend = i >= 5;
                final isTop = _weekdayOrders[i] == maxOrders && maxOrders > 0;
                final color = isWeekend ? colorWeekend : colorActive;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (isTop)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 3, vertical: 1),
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text('🏆',
                                style: const TextStyle(fontSize: 8)),
                          ),
                        const SizedBox(height: 2),
                        AnimatedContainer(
                          duration: Duration(milliseconds: 400 + i * 50),
                          curve: Curves.easeOutCubic,
                          height: (70 * ratio).clamp(3.0, 70.0),
                          decoration: BoxDecoration(
                            color: color.withOpacity(isTop ? 1.0 : 0.6),
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(4)),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 6),
          // Labels dos dias
          Row(
            children: List.generate(7, (i) => Expanded(
              child: Text(labels[i],
                  textAlign: TextAlign.center,
                  style: AppTypography.badge.copyWith(
                      fontSize: 9,
                      color: i >= 5
                          ? colorWeekend
                          : AppColors.textTertiary)),
            )),
          ),
          const SizedBox(height: 8),
          // Linha de estatísticas
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _heatmapStat('Pedidos', _ordersCount.toString()),
              _heatmapStat('Melhor dia', labels[_weekdayOrders
                  .indexWhere((v) => v == maxOrders)]),
              _heatmapStat('Pico faturamento',
                  labels[_weekdayRevenue.indexWhere((v) => v == maxRev)]),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heatmapStat(String label, String value) => Column(
    children: [
      Text(value, style: AppTypography.bodyBold.copyWith(fontSize: 13)),
      Text(label, style: AppTypography.caption.copyWith(
          color: AppColors.textTertiary, fontSize: 9)),
    ],
  );

  // ─────────────────────────────────────────────────────────────────────────
  // 🔔 Alertas de Clientes Sem Compra
  // ─────────────────────────────────────────────────────────────────────────

  Widget _inactiveClientsAlertCard() {
    if (_inactiveAlert.isEmpty) return const SizedBox.shrink();
    return _card(
      title: '🔔 Clientes para Contactar',
      subtitle: '${_inactiveAlert.length} sem compra recente',
      child: Column(
        children: _inactiveAlert.map((row) {
          final name    = row['name']?.toString() ?? '—';
          final daysAgo = (row['days_ago'] as num?)?.toInt() ?? 0;
          final isCritical = daysAgo >= 90;
          final badgeColor = isCritical
              ? AppColors.error
              : daysAgo >= 60
                  ? AppColors.warning
                  : const Color(0xFF0984E3);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: badgeColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('$daysAgo d',
                      style: AppTypography.badge.copyWith(
                          color: badgeColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 10)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(name,
                      style: AppTypography.body.copyWith(fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                const Icon(Icons.chevron_right_rounded,
                    size: 16, color: AppColors.textTertiary),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 📦 Produtos Recomendados
  // ─────────────────────────────────────────────────────────────────────────

  Widget _productRecommendationCard() {
    if (_recommendedProducts.isEmpty) return const SizedBox.shrink();
    return _card(
      title: '📦 Oportunidades do Mês',
      subtitle: 'Produtos sem venda em ${DateFormat('MMMM', 'pt_BR').format(DateTime.now())}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Estes produtos são seus mais vendidos historicamente'
            ' mas ainda não foram pedidos este mês.',
            style: AppTypography.caption.copyWith(
                color: AppColors.textTertiary, fontSize: 11),
          ),
          const SizedBox(height: 12),
          ..._recommendedProducts.asMap().entries.map((entry) {
            final i    = entry.key;
            final row  = entry.value;
            final name = row['product_name']?.toString() ??
                row['product_code']?.toString() ?? '?';
            final hist = (row['num_orders_hist'] as num?)?.toInt() ?? 0;
            final colors = [
              const Color(0xFF0984E3),
              const Color(0xFF6C5CE7),
              const Color(0xFF00B894),
              AppColors.warning,
              AppColors.error,
              const Color(0xFF636E72),
            ];
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: colors[i % colors.length].withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Center(
                      child: Text('${i + 1}',
                          style: AppTypography.badge.copyWith(
                              color: colors[i % colors.length],
                              fontWeight: FontWeight.bold,
                              fontSize: 11)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(name,
                        style: AppTypography.body.copyWith(fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00B894).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('$hist pedidos',
                        style: AppTypography.badge.copyWith(
                            color: const Color(0xFF00B894),
                            fontSize: 9,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }


  Widget _erpKpisCard() {
    final kpis = _erpKpis!;
    final metaPct = kpis.metaPercent;
    final metaColor = metaPct >= 100
        ? const Color(0xFF00B894)
        : metaPct >= 70
            ? const Color(0xFFFDAA48)
            : AppColors.error;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0984E3), Color(0xFF6C5CE7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0984E3).withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Dados Reais do ERP',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
              ),
              Text(
                'Sync ${DateFormat('HH:mm').format(DateTime.tryParse(kpis.syncedAt) ?? DateTime.now())}',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.7), fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Meta mensal
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Meta Mensal',
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 11)),
                    const SizedBox(height: 2),
                    Text(_cur.format(kpis.metaMensal),
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 18)),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: metaColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: metaColor, width: 1.5),
                ),
                child: Text(
                  '${metaPct.toStringAsFixed(1)}%',
                  style: TextStyle(
                      color: metaColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Barra de progresso da meta
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (metaPct / 100).clamp(0.0, 1.0),
              backgroundColor: Colors.white.withOpacity(0.2),
              valueColor: AlwaysStoppedAnimation(metaColor),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 16),
          // Métricas em grid 2x2
          Row(
            children: [
              Expanded(
                  child: _erpMiniKpi(
                      'Venda Mensal', _cur.format(kpis.vendaMensal))),
              const SizedBox(width: 12),
              Expanded(
                  child: _erpMiniKpi(
                      'Venda Hoje', _cur.format(kpis.vendaDiaria))),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                  child: _erpMiniKpi(
                      'Comissão Mensal', _cur.format(kpis.comissaoMensal))),
              const SizedBox(width: 12),
              Expanded(
                  child: _erpMiniKpi(
                      'Comissão Hoje', _cur.format(kpis.comissaoDiaria))),
            ],
          ),
          if (kpis.servicoMensal > 0) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                    child: _erpMiniKpi(
                        'Serviços', _cur.format(kpis.servicoMensal))),
                const SizedBox(width: 12),
                Expanded(
                    child: _erpMiniKpi('Comissão Serv.',
                        _cur.format(kpis.comissaoSvMensal))),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _erpMiniKpi(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  color: Colors.white.withOpacity(0.7), fontSize: 10)),
          const SizedBox(height: 2),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14)),
        ],
      );

  // ─────────────────────────────────────────────────────────────────────────
  // KPI cards with delta comparison
  // ─────────────────────────────────────────────────────────────────────────

  Widget _kpiRow() => Row(
    children: [
      Expanded(child: _kpiCard(
        'Total Vendas', _cur.format(_total),
        Icons.attach_money_rounded, AppColors.primary,
        delta: _prevTotal > 0 ? ((_total - _prevTotal) / _prevTotal * 100) : null,
      )),
      const SizedBox(width: 8),
      Expanded(child: _kpiCard(
        'Pedidos', '${_ordersCount}',
        Icons.receipt_long_rounded, AppColors.actionPrimary,
        delta: _prevCount > 0 ? ((_ordersCount - _prevCount) / _prevCount * 100) : null,
      )),
      const SizedBox(width: 8),
      Expanded(child: _kpiCard(
        'Ticket Médio', _cur.format(_avgTicket),
        Icons.trending_up_rounded, const Color(0xFF6C5CE7),
        delta: _prevAvgTicket > 0 ? ((_avgTicket - _prevAvgTicket) / _prevAvgTicket * 100) : null,
      )),
    ],
  );

  Widget _kpiCard(String label, String value, IconData icon, Color color,
      {double? delta}) {
    final hasComparison = delta != null && delta.isFinite;
    final isPositive = hasComparison && delta >= 0;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05),
            blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: color),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: AppTypography.headingMedium.copyWith(
                color: color, fontSize: 15)),
          ),
          const SizedBox(height: 2),
          Text(label, style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary, fontSize: 10)),
          if (hasComparison) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(isPositive ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                    size: 12, color: isPositive ? const Color(0xFF00B894) : AppColors.error),
                const SizedBox(width: 2),
                Text('${delta.abs().toStringAsFixed(0)}%',
                    style: AppTypography.badge.copyWith(
                      color: isPositive ? const Color(0xFF00B894) : AppColors.error,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    )),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Commission card
  // ─────────────────────────────────────────────────────────────────────────

  Widget _commissionCard() {
    if (_commissionRate == null || _commissionRate == 0) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2D3436), Color(0xFF636E72)],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.percent_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Comissão Estimada (${_commissionRate!.toStringAsFixed(1)}%)',
                  style: AppTypography.caption.copyWith(color: Colors.white70, fontSize: 11)),
              const SizedBox(height: 2),
              Text(_cur.format(_commission),
                  style: AppTypography.headingLarge.copyWith(color: Colors.white)),
            ],
          )),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Revenue line chart (fl_chart)
  // ─────────────────────────────────────────────────────────────────────────

  Widget _revenueChartSection() {
    if (_revenueByDay.isEmpty) return const SizedBox.shrink();

    final entries = _revenueByDay.entries.toList();
    final maxVal  = entries.fold(0.0, (m, e) => max(m, e.value));

    return _card(
      title: 'Evolução de Faturamento',
      child: SizedBox(
        height: 200,
        child: LineChart(
          LineChartData(
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: maxVal > 0 ? maxVal / 4 : 1,
              getDrawingHorizontalLine: (v) => FlLine(
                color: AppColors.border.withOpacity(0.5), strokeWidth: 0.5,
              ),
            ),
            titlesData: FlTitlesData(
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 50,
                  getTitlesWidget: (v, meta) {
                    if (v == meta.max || v == meta.min) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Text(_formatCompact(v),
                          style: AppTypography.badge.copyWith(
                            color: AppColors.textTertiary, fontSize: 9)),
                    );
                  },
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: max(1, (entries.length / 7).ceilToDouble()),
                  getTitlesWidget: (v, _) {
                    final idx = v.toInt();
                    if (idx < 0 || idx >= entries.length) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(entries[idx].key,
                          style: AppTypography.badge.copyWith(
                              color: AppColors.textTertiary, fontSize: 9)),
                    );
                  },
                ),
              ),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            borderData: FlBorderData(show: false),
            minY: 0,
            lineBarsData: [
              LineChartBarData(
                spots: entries.asMap().entries.map((e) =>
                    FlSpot(e.key.toDouble(), e.value.value)).toList(),
                isCurved: true,
                curveSmoothness: 0.25,
                color: AppColors.primary,
                barWidth: 2.5,
                isStrokeCapRound: true,
                dotData: FlDotData(
                  show: true,
                  getDotPainter: (sp, _, __, ___) => FlDotCirclePainter(
                    radius: sp.y > 0 ? 3 : 0,
                    color: AppColors.primary,
                    strokeWidth: 1.5,
                    strokeColor: Colors.white,
                  ),
                ),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.primary.withOpacity(0.25),
                      AppColors.primary.withOpacity(0.02),
                    ],
                  ),
                ),
              ),
            ],
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipItems: (spots) => spots.map((s) {
                  final idx = s.x.toInt();
                  final label = idx >= 0 && idx < entries.length ? entries[idx].key : '';
                  return LineTooltipItem(
                    '$label\n${_cur.format(s.y)}',
                    AppTypography.badge.copyWith(color: Colors.white, fontSize: 10),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Margin card
  // ─────────────────────────────────────────────────────────────────────────

  Widget _marginCard() {
    if (_grossRevenue <= 0) return const SizedBox.shrink();

    final profit = _grossRevenue - _estimatedCost;
    final marginPct = profit / _grossRevenue * 100;

    return _card(
      title: '💰 Margem Estimada',
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _miniKpi('Faturamento', _cur.format(_grossRevenue))),
              Expanded(child: _miniKpi('Custo Est.', _cur.format(_estimatedCost))),
              Expanded(child: _miniKpi('Lucro Bruto', _cur.format(profit),
                  color: profit > 0 ? const Color(0xFF00B894) : AppColors.error)),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: (marginPct / 100).clamp(0, 1),
              minHeight: 10,
              backgroundColor: AppColors.border,
              valueColor: AlwaysStoppedAnimation<Color>(
                marginPct > 20 ? const Color(0xFF00B894) :
                marginPct > 10 ? AppColors.warning : AppColors.error,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: Text('${marginPct.toStringAsFixed(1)}% de margem',
                style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary, fontSize: 11)),
          ),
        ],
      ),
    );
  }

  Widget _miniKpi(String label, String value, {Color? color}) => Column(
    children: [
      Text(value, style: AppTypography.bodyBold.copyWith(
          fontSize: 12, color: color ?? AppColors.textPrimary)),
      const SizedBox(height: 2),
      Text(label, style: AppTypography.badge.copyWith(
          color: AppColors.textTertiary, fontSize: 9)),
    ],
  );

  // ─────────────────────────────────────────────────────────────────────────
  // Discount analysis card
  // ─────────────────────────────────────────────────────────────────────────

  Widget _discountCard() {
    return _card(
      title: '🏷️ Descontos Concedidos',
      child: Column(
        children: [
          // Bruto = total líquido + descontos concedidos
          _infoRow('Total descontos', _cur.format(_totalDiscount),
              suffix: (_total + _totalDiscount) > 0
                  ? ' (${(_totalDiscount / (_total + _totalDiscount) * 100).toStringAsFixed(1)}%)'
                  : ''),
          _infoRow('Desc. médio/pedido',
              _ordersCount == 0 ? 'R\$ 0,00' : _cur.format(_totalDiscount / _ordersCount)),
          _infoRow('Pedidos com desconto',
              '$_ordersWithDisc de ${_ordersCount} (${_ordersCount == 0 ? 0 : (_ordersWithDisc / _ordersCount * 100).toStringAsFixed(0)}%)'),
          if (_ordersHighDisc > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, size: 14, color: AppColors.warning),
                  const SizedBox(width: 4),
                  Text('$_ordersHighDisc pedido${_ordersHighDisc > 1 ? 's' : ''} com desconto > 10%',
                      style: AppTypography.caption.copyWith(
                          color: AppColors.warning, fontSize: 11)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value, {String suffix = ''}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppTypography.body.copyWith(
            color: AppColors.textSecondary, fontSize: 12)),
        Text('$value$suffix', style: AppTypography.bodyBold.copyWith(fontSize: 12)),
      ],
    ),
  );

  // ─────────────────────────────────────────────────────────────────────────
  // Client health card
  // ─────────────────────────────────────────────────────────────────────────

  Widget _clientHealthCard() {
    return _card(
      title: '👥 Carteira de Clientes',
      child: Column(
        children: [
          _clientRow('🟢', 'Ativos (compraram recentes)', '$_activeClients'),
          _clientRow('🆕', 'Novos (1ª compra no período)', '$_newClients'),
          _clientRow('🟡', 'Inativos (30-90 dias)', '$_inactiveClients'),
          _clientRow('🔴', 'Perdidos (90+ dias)', '$_lostClients'),
          const Divider(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Taxa de retenção', style: AppTypography.body.copyWith(
                  color: AppColors.textSecondary, fontSize: 12)),
              Text(
                _totalClients > 0
                    ? '${((_activeClients / max(_totalClients, 1)) * 100).toStringAsFixed(0)}%'
                    : '—',
                style: AppTypography.bodyBold.copyWith(
                    fontSize: 13, color: const Color(0xFF00B894)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _clientRow(String emoji, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 14)),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: AppTypography.body.copyWith(
            color: AppColors.textSecondary, fontSize: 12))),
        Text(value, style: AppTypography.bodyBold.copyWith(fontSize: 13)),
      ],
    ),
  );

  // ─────────────────────────────────────────────────────────────────────────
  // Geography card
  // ─────────────────────────────────────────────────────────────────────────

  Widget _geographyCard() {
    // Fonte primária: ERP rankings (disponíveis independente do período selecionado).
    // Fallback: cidades dos pedidos locais no SQLite filtrados pelo período.
    if (_rankings != null && _rankings!.byRegion.isNotEmpty) {
      final regions = _rankings!.byRegion;
      final total = regions.fold(0.0, (s, e) => s + e.totalValue);
      final maxVal = regions.first.totalValue.clamp(1.0, double.infinity);

      return _card(
        title: '📍 Vendas por Região (ERP)',
        child: Column(
          children: regions.map((r) {
            final pct = total > 0 ? r.totalValue / total * 100 : 0.0;
            final ratio = r.totalValue / maxVal;
            final label = r.region.isNotEmpty ? '${r.region} (${r.uf})' : r.uf;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(label,
                          style: AppTypography.body.copyWith(fontSize: 12),
                          maxLines: 1, overflow: TextOverflow.ellipsis)),
                      Text(_cur.format(r.totalValue),
                          style: AppTypography.bodyBold.copyWith(fontSize: 11)),
                      const SizedBox(width: 6),
                      Text('${pct.toStringAsFixed(0)}%',
                          style: AppTypography.badge.copyWith(
                              color: AppColors.textTertiary, fontSize: 10)),
                    ],
                  ),
                  const SizedBox(height: 3),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: ratio,
                      backgroundColor: AppColors.border,
                      color: AppColors.actionPrimary,
                      minHeight: 4,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      );
    }

    // Sem dados ERP: mostra card vazio
    return _emptyPeriodCard(
      icon: Icons.location_on_outlined,
      title: '📍 Vendas por Região',
      period: 'Mês atual',
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Category mix card
  // ─────────────────────────────────────────────────────────────────────────

  Widget _categoryMixCard() {
    if (_categoryMix.isEmpty) return const SizedBox.shrink();

    final total = _categoryMix.fold(0.0, (s, e) => s + e.value);
    final maxVal = _categoryMix.first.value;
    final colors = [
      AppColors.primary,
      const Color(0xFF6C5CE7),
      const Color(0xFF00B894),
      AppColors.warning,
      AppColors.error,
      const Color(0xFF636E72),
    ];

    return _card(
      title: '📦 Mix por Categoria',
      child: Column(
        children: _categoryMix.asMap().entries.map((entry) {
          final idx  = entry.key;
          final e    = entry.value;
          final pct  = total > 0 ? e.value / total * 100 : 0.0;
          final ratio = maxVal > 0 ? e.value / maxVal : 0.0;
          final color = colors[idx % colors.length];

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Container(width: 10, height: 10,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.key, style: AppTypography.body.copyWith(fontSize: 12),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: ratio,
                        backgroundColor: AppColors.border,
                        color: color,
                        minHeight: 4,
                      ),
                    ),
                  ],
                )),
                const SizedBox(width: 8),
                Text('${pct.toStringAsFixed(0)}%',
                    style: AppTypography.bodyBold.copyWith(fontSize: 11)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Top products
  // ─────────────────────────────────────────────────────────────────────────

  Widget _topProductsSection() {
    // Fonte primária: ERP rankings (todos os períodos).
    // Fallback: dados locais SQLite filtrados pelo período.
    if (_rankings != null && _rankings!.topProducts.isNotEmpty) {
      final products = _rankings!.topProducts;
      final maxVal = products.first.totalValue.clamp(1.0, double.infinity);

      return _card(
        title: 'Top ${products.length} Produtos (ERP)',
        child: Column(
          children: products.asMap().entries.map((entry) {
            final rank  = entry.key + 1;
            final p     = entry.value;
            final ratio = p.totalValue / maxVal;

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: Text('$rank°',
                        style: AppTypography.badge.copyWith(
                            color: rank <= 3 ? AppColors.warning : AppColors.textSecondary,
                            fontWeight: FontWeight.bold)),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.name,
                            style: AppTypography.body.copyWith(fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: ratio,
                            backgroundColor: AppColors.border,
                            color: AppColors.primary,
                            minHeight: 4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(_cur.format(p.totalValue),
                          style: AppTypography.badge.copyWith(
                              color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                      Text('${p.totalQty.toStringAsFixed(0)} un · ${p.numOrders} ped.',
                          style: AppTypography.badge.copyWith(
                              color: AppColors.textTertiary, fontSize: 9)),
                    ],
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      );
    }

    // Sem dados ERP: mostra card vazio
    return _emptyPeriodCard(
      icon: Icons.inventory_2_outlined,
      title: 'Top Produtos',
      period: 'Mês atual',
    );
  }



  // ─────────────────────────────────────────────────────────────────────────
  // Top customers
  // ─────────────────────────────────────────────────────────────────────────

  Widget _topCustomersSection() {
    // Fonte primária: ERP rankings (todos os períodos).
    // Fallback: dados locais SQLite filtrados pelo período.
    if (_rankings != null && _rankings!.topClients.isNotEmpty) {
      final clients = _rankings!.topClients;
      final maxVal = clients.first.totalValue.clamp(1.0, double.infinity);

      return _card(
        title: 'Top ${clients.length} Clientes (ERP)',
        child: Column(
          children: clients.asMap().entries.map((entry) {
            final rank  = entry.key + 1;
            final c     = entry.value;
            final ratio = c.totalValue / maxVal;

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: Text('$rank°',
                        style: AppTypography.badge.copyWith(
                            color: rank == 1 ? const Color(0xFFF9A825) : AppColors.textSecondary,
                            fontWeight: FontWeight.bold)),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.name,
                            style: AppTypography.body.copyWith(fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: ratio,
                            backgroundColor: AppColors.border,
                            color: AppColors.actionPrimary,
                            minHeight: 4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(_cur.format(c.totalValue),
                          style: AppTypography.badge.copyWith(color: AppColors.textSecondary)),
                      Text('${c.numOrders} ped.',
                          style: AppTypography.badge.copyWith(
                              color: AppColors.textTertiary, fontSize: 9)),
                    ],
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      );
    }

    // Dados locais do SQLite (filtrados pelo período selecionado)
    if (_topCustomers.isEmpty) {
      return _emptyPeriodCard(
        icon: Icons.people_outline_rounded,
        title: 'Top Clientes',
        period: _period.label,
      );
    }

    final maxValue = _topCustomers.first.value.clamp(1.0, double.infinity);

    return _card(
      title: 'Top ${_topCustomers.length} Clientes — ${_period.label}',

      child: Column(
        children: _topCustomers.asMap().entries.map((entry) {
          final rank  = entry.key + 1;
          final name  = entry.value.key;
          final value = entry.value.value;
          final ratio = value / maxValue;

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: Text('$rank°',
                      style: AppTypography.badge.copyWith(
                          color: rank == 1 ? const Color(0xFFF9A825) : AppColors.textSecondary,
                          fontWeight: FontWeight.bold)),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: AppTypography.body.copyWith(fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: ratio,
                          backgroundColor: AppColors.border,
                          color: AppColors.actionPrimary,
                          minHeight: 4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(_cur.format(value),
                    style: AppTypography.badge.copyWith(color: AppColors.textSecondary)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

  Widget _card({required String title, String? subtitle, required Widget child}) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05),
          blurRadius: 8, offset: const Offset(0, 2))],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(title,
                  style: AppTypography.headingMedium.copyWith(fontSize: 14)),
            ),
            if (subtitle != null)
              Text(subtitle,
                  style: AppTypography.caption.copyWith(
                      color: AppColors.textTertiary, fontSize: 10)),
          ],
        ),
        const SizedBox(height: 12),
        child,
      ],
    ),
  );

  /// Card vazio — exibido quando não há dados locais no período selecionado.
  Widget _emptyPeriodCard({
    required IconData icon,
    required String title,
    required String period,
  }) =>
    Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05),
            blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppColors.textTertiary),
              const SizedBox(width: 6),
              Text(title, style: AppTypography.headingMedium.copyWith(
                  fontSize: 14, color: AppColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 16),
          Center(
            child: Column(
              children: [
                Icon(Icons.search_off_rounded, size: 36,
                    color: AppColors.textTertiary.withOpacity(0.5)),
                const SizedBox(height: 8),
                Text(
                  'Sem registros para "$period"',
                  style: AppTypography.body.copyWith(
                      color: AppColors.textTertiary, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  'Os dados aparecem conforme pedidos '
                  'são realizados no período.',
                  textAlign: TextAlign.center,
                  style: AppTypography.caption.copyWith(
                      color: AppColors.textTertiary, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );

  Widget _emptyState() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.insert_chart_outlined, size: 64,
            color: AppColors.textTertiary.withOpacity(0.4)),
        const SizedBox(height: 16),
        Text('Sem dados para o período selecionado',
            style: AppTypography.body.copyWith(color: AppColors.textTertiary)),
      ],
    ),
  );

  String _formatCompact(double v) {
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}k';
    return v.toStringAsFixed(0);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _PeriodFilter widget
// ─────────────────────────────────────────────────────────────────────────────

class _PeriodFilter extends StatelessWidget {
  final _Period selected;
  final DateTime? customFrom;
  final DateTime? customTo;
  final ValueChanged<_Period> onPeriodChanged;
  final VoidCallback onCustomTap;

  const _PeriodFilter({
    required this.selected,
    this.customFrom,
    this.customTo,
    required this.onPeriodChanged,
    required this.onCustomTap,
  });

  bool get _hasCustom => customFrom != null && customTo != null;

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('dd/MM', 'pt_BR');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            ..._Period.values.map((p) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(p.label, style: AppTypography.caption.copyWith(
                        color: selected == p && !_hasCustom
                            ? Colors.white
                            : AppColors.textSecondary,
                        fontWeight: FontWeight.w600)),
                    selected: selected == p && !_hasCustom,
                    onSelected: (_) => onPeriodChanged(p),
                    selectedColor: AppColors.actionPrimary,
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: AppColors.border),
                    showCheckmark: selected == p && !_hasCustom,
                    checkmarkColor: Colors.white,
                  ),
                )),
            ChoiceChip(
              avatar: Icon(Icons.calendar_month_rounded, size: 16,
                  color: _hasCustom ? Colors.white : AppColors.textSecondary),
              label: Text(
                _hasCustom
                    ? '${dateFmt.format(customFrom!)} – ${dateFmt.format(customTo!)}'
                    : 'Personalizado',
                style: AppTypography.caption.copyWith(
                    color: _hasCustom ? Colors.white : AppColors.textSecondary,
                    fontWeight: FontWeight.w600),
              ),
              selected: _hasCustom,
              onSelected: (_) => onCustomTap(),
              selectedColor: AppColors.actionPrimary,
              backgroundColor: Colors.white,
              side: const BorderSide(color: AppColors.border),
              showCheckmark: false,
            ),
          ],
        ),
      ),
    );
  }
}





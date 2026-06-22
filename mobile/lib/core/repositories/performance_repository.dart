/// PerformanceRepository — Repositório de KPIs de desempenho reais do ERP.
///
/// Responsabilidades:
/// - Persistir dados vindos da procedure MINHASVENDAS (Firebird) no SQLite
/// - Prover acesso offline-first aos KPIs de vendas, comissão e metas
/// - Persistir e ler rankings de vendas reais do ERP (L_VENDAS_*)
///
/// Fluxo: SyncService.pullPerformance() → API → PerformanceRepository → SQLite
library;

import 'dart:convert';
import '../database/database_helper.dart';

/// Snapshot dos KPIs reais do vendedor vindos do ERP.
class SellerKpis {
  final String sellerId;
  final int month;
  final int year;
  final double vendaDiaria;
  final double vendaMensal;
  final double comissaoDiaria;
  final double comissaoMensal;
  final double metaDiaria;
  final double metaMensal;
  final double servicoMensal;
  final double comissaoSvMensal;
  final double totalDiario;
  final double totalMensal;
  final double comissaoDiariaR;
  final double comissaoMensalR;
  final String syncedAt;

  const SellerKpis({
    required this.sellerId,
    required this.month,
    required this.year,
    this.vendaDiaria = 0,
    this.vendaMensal = 0,
    this.comissaoDiaria = 0,
    this.comissaoMensal = 0,
    this.metaDiaria = 0,
    this.metaMensal = 0,
    this.servicoMensal = 0,
    this.comissaoSvMensal = 0,
    this.totalDiario = 0,
    this.totalMensal = 0,
    this.comissaoDiariaR = 0,
    this.comissaoMensalR = 0,
    this.syncedAt = '',
  });

  /// Indica se há dados reais sincronizados do ERP (não é apenas o fallback local sem sync).
  bool get hasData => syncedAt.isNotEmpty;

  /// Percentual de atingimento da meta mensal.
  double get metaPercent => metaMensal > 0 ? (vendaMensal / metaMensal * 100) : 0;

  /// Percentual de atingimento da meta diária.
  double get metaDiariaPercent => metaDiaria > 0 ? (vendaDiaria / metaDiaria * 100) : 0;

  /// Cria a partir do mapa retornado pelo middleware (JSON).
  factory SellerKpis.fromApi(Map<String, dynamic> json) {
    return SellerKpis(
      sellerId:         json['sellerId']?.toString() ?? '',
      month:            (json['month'] as num?)?.toInt() ?? DateTime.now().month,
      year:             (json['year'] as num?)?.toInt() ?? DateTime.now().year,
      vendaDiaria:      (json['vendaDiaria'] as num?)?.toDouble() ?? 0,
      vendaMensal:      (json['vendaMensal'] as num?)?.toDouble() ?? 0,
      comissaoDiaria:   (json['comissaoDiaria'] as num?)?.toDouble() ?? 0,
      comissaoMensal:   (json['comissaoMensal'] as num?)?.toDouble() ?? 0,
      metaDiaria:       (json['metaDiaria'] as num?)?.toDouble() ?? 0,
      metaMensal:       (json['metaMensal'] as num?)?.toDouble() ?? 0,
      servicoMensal:    (json['servicoMensal'] as num?)?.toDouble() ?? 0,
      comissaoSvMensal: (json['comissaoSvMensal'] as num?)?.toDouble() ?? 0,
      totalDiario:      (json['totalDiario'] as num?)?.toDouble() ?? 0,
      totalMensal:      (json['totalMensal'] as num?)?.toDouble() ?? 0,
      comissaoDiariaR:  (json['comissaoDiariaR'] as num?)?.toDouble() ?? 0,
      comissaoMensalR:  (json['comissaoMensalR'] as num?)?.toDouble() ?? 0,
      syncedAt:         json['syncedAt']?.toString() ?? DateTime.now().toIso8601String(),
    );
  }

  /// Cria a partir do mapa do SQLite.
  factory SellerKpis.fromMap(Map<String, dynamic> map) {
    return SellerKpis(
      sellerId:         map['seller_id']?.toString() ?? '',
      month:            (map['month'] as num?)?.toInt() ?? 0,
      year:             (map['year'] as num?)?.toInt() ?? 0,
      vendaDiaria:      (map['venda_diaria'] as num?)?.toDouble() ?? 0,
      vendaMensal:      (map['venda_mensal'] as num?)?.toDouble() ?? 0,
      comissaoDiaria:   (map['comissao_diaria'] as num?)?.toDouble() ?? 0,
      comissaoMensal:   (map['comissao_mensal'] as num?)?.toDouble() ?? 0,
      metaDiaria:       (map['meta_diaria'] as num?)?.toDouble() ?? 0,
      metaMensal:       (map['meta_mensal'] as num?)?.toDouble() ?? 0,
      servicoMensal:    (map['servico_mensal'] as num?)?.toDouble() ?? 0,
      comissaoSvMensal: (map['comissao_sv_mensal'] as num?)?.toDouble() ?? 0,
      totalDiario:      (map['total_diario'] as num?)?.toDouble() ?? 0,
      totalMensal:      (map['total_mensal'] as num?)?.toDouble() ?? 0,
      comissaoDiariaR:  (map['comissao_diaria_r'] as num?)?.toDouble() ?? 0,
      comissaoMensalR:  (map['comissao_mensal_r'] as num?)?.toDouble() ?? 0,
      syncedAt:         map['synced_at']?.toString() ?? '',
    );
  }

  /// Converte para mapa do SQLite.
  Map<String, dynamic> toMap() => {
    'seller_id':          sellerId,
    'month':              month,
    'year':               year,
    'venda_diaria':       vendaDiaria,
    'venda_mensal':       vendaMensal,
    'comissao_diaria':    comissaoDiaria,
    'comissao_mensal':    comissaoMensal,
    'meta_diaria':        metaDiaria,
    'meta_mensal':        metaMensal,
    'servico_mensal':     servicoMensal,
    'comissao_sv_mensal': comissaoSvMensal,
    'total_diario':       totalDiario,
    'total_mensal':       totalMensal,
    'comissao_diaria_r':  comissaoDiariaR,
    'comissao_mensal_r':  comissaoMensalR,
    'synced_at':          syncedAt,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Rankings de vendas reais do ERP (L_VENDAS_*)
// ─────────────────────────────────────────────────────────────────────────────

/// Produto ranqueado por valor de vendas do ERP.
class RankedProduct {
  final String name;
  final int productId;
  final double totalQty;
  final double totalValue;
  final int numOrders;

  const RankedProduct({
    required this.name,
    required this.productId,
    required this.totalQty,
    required this.totalValue,
    required this.numOrders,
  });

  factory RankedProduct.fromJson(Map<String, dynamic> json) {
    return RankedProduct(
      name:       json['name']?.toString() ?? '',
      productId:  (json['productId'] as num?)?.toInt() ?? 0,
      totalQty:   (json['totalQty'] as num?)?.toDouble() ?? 0,
      totalValue: (json['totalValue'] as num?)?.toDouble() ?? 0,
      numOrders:  (json['numOrders'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Cliente ranqueado por valor de vendas do ERP.
class RankedClient {
  final String name;
  final int clientId;
  final double totalValue;
  final int numOrders;

  const RankedClient({
    required this.name,
    required this.clientId,
    required this.totalValue,
    required this.numOrders,
  });

  factory RankedClient.fromJson(Map<String, dynamic> json) {
    return RankedClient(
      name:       json['name']?.toString() ?? '',
      clientId:   (json['clientId'] as num?)?.toInt() ?? 0,
      totalValue: (json['totalValue'] as num?)?.toDouble() ?? 0,
      numOrders:  (json['numOrders'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Vendas por região do ERP.
class RegionSales {
  final String region;
  final String uf;
  final double totalValue;
  final int numOrders;

  const RegionSales({
    required this.region,
    required this.uf,
    required this.totalValue,
    required this.numOrders,
  });

  factory RegionSales.fromJson(Map<String, dynamic> json) {
    return RegionSales(
      region:     json['region']?.toString() ?? '',
      uf:         json['uf']?.toString() ?? '',
      totalValue: (json['totalValue'] as num?)?.toDouble() ?? 0,
      numOrders:  (json['numOrders'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Vendedor ranqueado por valor de vendas do ERP (ranking da equipe).
class RankedSeller {
  final String sellerId;
  final String name;
  final double totalValue;
  final int numOrders;

  const RankedSeller({
    required this.sellerId,
    required this.name,
    required this.totalValue,
    required this.numOrders,
  });

  factory RankedSeller.fromJson(Map<String, dynamic> json) {
    return RankedSeller(
      sellerId:   json['sellerId']?.toString() ?? '',
      name:       json['name']?.toString() ?? '',
      totalValue: (json['totalValue'] as num?)?.toDouble() ?? 0,
      numOrders:  (json['numOrders'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Faturamento por dia do ERP
class ErpRevenueByDay {
  final String date;
  final double totalAmount;
  const ErpRevenueByDay(this.date, this.totalAmount);
  factory ErpRevenueByDay.fromJson(Map<String, dynamic> json) => ErpRevenueByDay(
    json['date']?.toString() ?? '',
    (json['totalAmount'] as num?)?.toDouble() ?? 0,
  );
}

/// Saúde da carteira de clientes do ERP
class ErpClientHealth {
  final int actives;
  final int inactives;
  final int lost;
  const ErpClientHealth({this.actives = 0, this.inactives = 0, this.lost = 0});
  factory ErpClientHealth.fromJson(Map<String, dynamic> json) => ErpClientHealth(
    actives: (json['actives'] as num?)?.toInt() ?? 0,
    inactives: (json['inactives'] as num?)?.toInt() ?? 0,
    lost: (json['lost'] as num?)?.toInt() ?? 0,
  );
}

/// Curva ABC / Mix de Categorias do ERP
class ErpCategoryMix {
  final String name;
  final double total;
  const ErpCategoryMix(this.name, this.total);
  factory ErpCategoryMix.fromJson(Map<String, dynamic> json) => ErpCategoryMix(
    json['name']?.toString() ?? '',
    (json['total'] as num?)?.toDouble() ?? 0,
  );
}

/// Heatmap de dias da semana do ERP
class ErpHeatmapStat {
  final int dayOfWeek;
  final double totalAmount;
  const ErpHeatmapStat(this.dayOfWeek, this.totalAmount);
  factory ErpHeatmapStat.fromJson(Map<String, dynamic> json) => ErpHeatmapStat(
    (json['dayOfWeek'] as num?)?.toInt() ?? 0,
    (json['totalAmount'] as num?)?.toDouble() ?? 0,
  );
}

/// Snapshot completo dos rankings de vendas de um vendedor.
class SalesRankings {
  final List<RankedProduct> topProducts;
  final List<RankedClient>  topClients;
  final List<RegionSales>   byRegion;
  final List<RankedSeller>    bySeller;   // ranking da equipe
  final List<ErpRevenueByDay> revenueByDay;
  final ErpClientHealth       clientHealth;
  final List<ErpCategoryMix>  categoryMix;
  final List<ErpHeatmapStat>  heatmapStats;
  final String syncedAt;

  const SalesRankings({
    required this.topProducts,
    required this.topClients,
    required this.byRegion,
    this.bySeller = const [],
    this.revenueByDay = const [],
    this.clientHealth = const ErpClientHealth(),
    this.categoryMix = const [],
    this.heatmapStats = const [],
    required this.syncedAt,
  });

  bool get hasData => topProducts.isNotEmpty || topClients.isNotEmpty
      || byRegion.isNotEmpty || bySeller.isNotEmpty || revenueByDay.isNotEmpty;

  factory SalesRankings.fromMap(Map<String, dynamic> map) {
    final products = _parseJsonList(map['top_products_json'])
        .map((e) => RankedProduct.fromJson(e as Map<String, dynamic>))
        .toList();
    final clients = _parseJsonList(map['top_clients_json'])
        .map((e) => RankedClient.fromJson(e as Map<String, dynamic>))
        .toList();
    final regions = _parseJsonList(map['by_region_json'])
        .map((e) => RegionSales.fromJson(e as Map<String, dynamic>))
        .toList();
    final sellers = _parseJsonList(map['by_seller_json'])
        .map((e) => RankedSeller.fromJson(e as Map<String, dynamic>))
        .toList();
    
    final rbd = _parseJsonList(map['revenue_by_day_json'])
        .map((e) => ErpRevenueByDay.fromJson(e as Map<String, dynamic>))
        .toList();
    final chObj = _parseJsonObject(map['client_health_json']);
    final ch = chObj.isNotEmpty ? ErpClientHealth.fromJson(chObj) : const ErpClientHealth();
    
    final mix = _parseJsonList(map['category_mix_json'])
        .map((e) => ErpCategoryMix.fromJson(e as Map<String, dynamic>))
        .toList();
    final hs = _parseJsonList(map['heatmap_stats_json'])
        .map((e) => ErpHeatmapStat.fromJson(e as Map<String, dynamic>))
        .toList();

    return SalesRankings(
      topProducts: products,
      topClients:  clients,
      byRegion:    regions,
      bySeller:    sellers,
      revenueByDay: rbd,
      clientHealth: ch,
      categoryMix:  mix,
      heatmapStats: hs,
      syncedAt:    map['synced_at']?.toString() ?? '',
    );
  }

  /// Cria SalesRankings a partir de JSON da API (resposta on-demand — sem SQLite).
  factory SalesRankings.fromApiJson(Map<String, dynamic> json) {
    List<T> parseList<T>(String key, T Function(Map<String, dynamic>) fromJson) =>
        ((json[key] as List?)?.cast<Map<String, dynamic>>() ?? [])
            .map(fromJson).toList();

    final ch = json['clientHealth'] as Map<String, dynamic>?;

    return SalesRankings(
      topProducts: parseList('topProducts', RankedProduct.fromJson),
      topClients:  parseList('topClients',  RankedClient.fromJson),
      byRegion:    parseList('byRegion',    RegionSales.fromJson),
      bySeller:    parseList('bySeller',    RankedSeller.fromJson),
      revenueByDay: parseList('revenueByDay', ErpRevenueByDay.fromJson),
      clientHealth: ch != null ? ErpClientHealth.fromJson(ch) : const ErpClientHealth(),
      categoryMix:  parseList('categoryMix',  ErpCategoryMix.fromJson),
      heatmapStats: parseList('heatmapStats', ErpHeatmapStat.fromJson),
      syncedAt: json['syncedAt']?.toString() ?? '',
    );
  }

  static List<dynamic> _parseJsonList(dynamic value) {
    if (value is String && value.isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is List) return decoded;
      } catch (_) {}
    }
    return [];
  }

  static Map<String, dynamic> _parseJsonObject(dynamic value) {
    if (value is String && value.isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {}
    }
    return {};
  }
}

class PerformanceRepository {
  final DatabaseHelper _db;

  PerformanceRepository(this._db);

  /// Salva os KPIs de desempenho do vendedor no SQLite (upsert por seller/month/year).
  Future<void> save(SellerKpis kpis) async {
    await _db.upsertSellerKpis(kpis.toMap());
  }

  /// Retorna os KPIs mais recentes do vendedor para o mês/ano.
  ///
  /// Se não houver dados, retorna null (fallback para dados locais na UI).
  Future<SellerKpis?> get(String companyId, String sellerId, {int? month, int? year}) async {
    final now = DateTime.now();
    final m = month ?? now.month;
    final y = year ?? now.year;
    final map = await _db.getSellerKpis(companyId, sellerId, m, y);
    return map != null ? SellerKpis.fromMap(map) : null;
  }

  /// Retorna os rankings de vendas reais do ERP para o mês/ano.
  ///
  /// Se não houver dados sincronizados, retorna null.
  Future<SalesRankings?> getRankings(String companyId, String sellerId, {int? month, int? year, String period = 'month'}) async {
    final now = DateTime.now();
    final m = month ?? now.month;
    final y = year ?? now.year;
    final map = await _db.getSalesRankings(companyId, sellerId, m, y, period: period);
    return map != null ? SalesRankings.fromMap(map) : null;
  }

  /// Converte resposta JSON on-demand (sem SQLite) num SalesRankings em memória.
  ///
  /// Usado pelo período personalizado — os dados não são persistidos localmente.
  SalesRankings? rankingsFromApiJson(Map<String, dynamic> json) {
    try {
      return SalesRankings.fromApiJson(json);
    } catch (e) {
      return null;
    }
  }
}


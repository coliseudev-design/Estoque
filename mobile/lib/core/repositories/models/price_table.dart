/// PriceTable e ProductPrice — Modelos para tabelas de preço do ERP.
///
/// Mapeado de TABELA_PRECOS (cabeçalho) e TABELA_PRECOS_ITENS (itens)
/// via procedure MOB_TABELAPRECO.
library;

// ─────────────────────────────────────────────────────────────────────────────
// PriceTable — cabeçalho da tabela de preço
// ─────────────────────────────────────────────────────────────────────────────

/// Tabela de preço cadastrada no ERP (TABELA_PRECOS).
///
/// [markupPct] é o percentual de acréscimo sobre o preço base de tabela.
/// Fórmula de cálculo (procedure MOB_TABELAPRECO):
///   PRECO = PRECO_BASE + (PRECO_BASE × markupPct / 100)
class PriceTable {
  final String id;
  final String name;

  /// Percentual de markup sobre o preço base (TABELA_PRECOS.PRECOT_P).
  final double markupPct;

  const PriceTable({
    required this.id,
    required this.name,
    this.markupPct = 0.0,
  });

  factory PriceTable.fromJson(Map<String, dynamic> json) {
    return PriceTable(
      id:        (json['id'] ?? json['ID'] ?? '').toString(),
      name:      (json['name'] as String? ?? '').trim(),
      markupPct: _toDouble(json['markupPct'] ?? json['markuppct'] ?? 0),
    );
  }

  Map<String, dynamic> toMap() => {
    'id':         id,
    'name':       name,
    'markup_pct': markupPct,
  };

  factory PriceTable.fromMap(Map<String, dynamic> map) {
    return PriceTable(
      id:        map['id'] as String,
      name:      map['name'] as String,
      markupPct: (map['markup_pct'] as num? ?? 0).toDouble(),
    );
  }

  static double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  @override
  String toString() => name;

  @override
  bool operator ==(Object other) => other is PriceTable && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

// ─────────────────────────────────────────────────────────────────────────────
// ProductPrice — preço de um produto em uma tabela específica
// ─────────────────────────────────────────────────────────────────────────────

/// Preço calculado pelo Firebird para produto × tabela.
/// Gerado por MOB_TABELAPRECO: PRECO = PRECO_BASE + (PRECO_BASE × PRECOT_P%).
class ProductPrice {
  final String productCode;
  final String priceTableId;
  final double price;

  const ProductPrice({
    required this.productCode,
    required this.priceTableId,
    required this.price,
  });

  factory ProductPrice.fromJson(Map<String, dynamic> json) {
    return ProductPrice(
      productCode:  (json['productCode'] ?? json['productcode'] ?? '').toString(),
      priceTableId: (json['priceTableId'] ?? json['pricetableid'] ?? '').toString(),
      price:        _toDouble(json['price'] ?? 0),
    );
  }

  Map<String, dynamic> toMap() => {
    'product_code':   productCode,
    'price_table_id': priceTableId,
    'price':          price,
  };

  factory ProductPrice.fromMap(Map<String, dynamic> map) {
    return ProductPrice(
      productCode:  map['product_code'] as String,
      priceTableId: map['price_table_id'] as String,
      price:        (map['price'] as num).toDouble(),
    );
  }

  static double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }
}

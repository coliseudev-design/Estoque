/// PaymentSpecies — Forma/Espécie de pagamento do ERP.
///
/// Mapeado da tabela ESPECIE_PGTO do Firebird via view MOB.
/// Exemplo: BOLETO BANCARIO, PIX OU A VISTA, DUPLICATA, etc.
library;

/// Espécie de pagamento disponível para pedidos.
class PaymentSpecies {
  final String id;
  final String name;
  final String? type;
  final int? days;

  const PaymentSpecies({
    required this.id,
    required this.name,
    this.type,
    this.days,
  });

  /// Descrição amigável: somente o nome da espécie (sem número de dias do ERP).
  String get displayName => name;

  factory PaymentSpecies.fromMap(Map<String, dynamic> map) {
    return PaymentSpecies(
      id:   (map['id'] ?? map['payment_species_id'])?.toString() ?? '',
      name: (map['name'] as String? ?? '').trim(),
      type: map['type'] as String?,
      days: _toInt(map['days']),
    );
  }

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    return int.tryParse(v.toString());
  }

  Map<String, dynamic> toMap() => {
    'payment_species_id': id,
    'name':               name,
    'type':               type,
    'days':               days,
  };

  @override
  String toString() => displayName;

  @override
  bool operator ==(Object other) => other is PaymentSpecies && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

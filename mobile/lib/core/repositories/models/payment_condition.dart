class PaymentCondition {
  final String id;
  final String descricao;
  final String? specieId;
  final double? descontoMax;
  final int? parcelas;
  final int? diasEntrada;
  final int? diasParcelas;
  final int? mobOrdem;

  const PaymentCondition({
    required this.id,
    required this.descricao,
    this.specieId,
    this.descontoMax,
    this.parcelas,
    this.diasEntrada,
    this.diasParcelas,
    this.mobOrdem,
  });

  factory PaymentCondition.fromJson(Map<String, dynamic> json) {
    return PaymentCondition(
      id: json['id'],
      descricao: json['descricao'],
      specieId: json['especieId']?.toString() ?? json['specieId']?.toString(),
      descontoMax: json['descontoMax'] != null ? (json['descontoMax'] as num).toDouble() : null,
      parcelas: json['parcelas'] as int?,
      diasEntrada: json['diasEntrada'] as int?,
      diasParcelas: json['diasParcelas'] as int?,
      mobOrdem: json['mobOrdem'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'descricao': descricao,
      'specieId': specieId,
      'descontoMax': descontoMax,
      'parcelas': parcelas,
      'diasEntrada': diasEntrada,
      'diasParcelas': diasParcelas,
      'mobOrdem': mobOrdem,
    };
  }

  // Helper for database insertion
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'descricao': descricao,
      'especie_id': specieId,
      'desconto_max': descontoMax,
      'parcelas': parcelas,
      'dias_entrada': diasEntrada,
      'dias_parcelas': diasParcelas,
      'mob_ordem': mobOrdem,
    };
  }

  factory PaymentCondition.fromMap(Map<String, dynamic> map) {
    // null-safe: filas antigas podem ter id=null (sync com chaves lowercase incorretas)
    final id = map['id']?.toString() ?? '';
    if (id.isEmpty) return PaymentCondition(id: '', descricao: '');
    return PaymentCondition(
      id: id,
      descricao: (map['descricao'] as String?) ?? '',
      specieId: map['especie_id']?.toString(),
      descontoMax: map['desconto_max'] != null ? (map['desconto_max'] as num).toDouble() : null,
      parcelas: map['parcelas'] as int?,
      diasEntrada: map['dias_entrada'] as int?,
      diasParcelas: map['dias_parcelas'] as int?,
      mobOrdem: map['mob_ordem'] as int?,
    );
  }
}

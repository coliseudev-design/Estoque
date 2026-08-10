class PaymentConditionModel {
  final String id;
  final int? especieId;
  final int? formaId;
  final String descricao;

  PaymentConditionModel({
    required this.id,
    this.especieId,
    this.formaId,
    required this.descricao,
  });

  factory PaymentConditionModel.fromMap(Map<String, dynamic> map) {
    return PaymentConditionModel(
      id: map['id'] as String,
      especieId: map['especieId'] as int? ?? map['especie_id'] as int?,
      formaId: map['formaId'] as int? ?? map['forma_id'] as int?,
      descricao: map['descricao'] as String,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'especie_id': especieId,
      'forma_id': formaId,
      'descricao': descricao,
    };
  }
}

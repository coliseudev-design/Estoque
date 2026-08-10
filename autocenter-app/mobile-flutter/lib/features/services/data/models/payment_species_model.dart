class PaymentSpeciesModel {
  final int id;
  final String description;
  final String? tipo;

  PaymentSpeciesModel({
    required this.id,
    required this.description,
    this.tipo,
  });

  factory PaymentSpeciesModel.fromMap(Map<String, dynamic> map) {
    return PaymentSpeciesModel(
      id: map['id'] as int,
      description: map['description'] as String,
      tipo: map['tipo'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'description': description,
      'tipo': tipo,
    };
  }
}

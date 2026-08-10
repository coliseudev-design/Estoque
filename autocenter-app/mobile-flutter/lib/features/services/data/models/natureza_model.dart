class NaturezaModel {
  final int id;
  final String descricao;
  final String? descricaoNota;
  final String? codigoFiscal;
  final int? es;
  final int? processo;
  final int? tipo;
  final int? mobOrdem;

  NaturezaModel({
    required this.id,
    required this.descricao,
    this.descricaoNota,
    this.codigoFiscal,
    this.es,
    this.processo,
    this.tipo,
    this.mobOrdem,
  });

  factory NaturezaModel.fromMap(Map<String, dynamic> map) {
    return NaturezaModel(
      id: map['id'] as int,
      descricao: map['descricao'] as String,
      descricaoNota: map['descricaoNota'] as String? ?? map['descricao_nota'] as String?,
      codigoFiscal: map['codigoFiscal'] as String? ?? map['codigo_fiscal'] as String?,
      es: map['es'] as int?,
      processo: map['processo'] as int?,
      tipo: map['tipo'] as int?,
      mobOrdem: map['mobOrdem'] as int? ?? map['mob_ordem'] as int?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'descricao': descricao,
      'descricao_nota': descricaoNota,
      'codigo_fiscal': codigoFiscal,
      'es': es,
      'processo': processo,
      'tipo': tipo,
      'mob_ordem': mobOrdem,
    };
  }
}

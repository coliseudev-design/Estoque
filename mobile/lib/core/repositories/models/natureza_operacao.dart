/// NaturezaOperacao — Natureza de Operação do ERP (NATUREZA_OPERACAO).
///
/// Define o tipo fiscal da operação (venda dentro do estado, fora, bonificação etc.).
/// Somente naturezas com MOB_ACESSO = 'S' aparecem no app móvel.
library;

/// Natureza de Operação disponível para pedidos no app.
class NaturezaOperacao {
  final String id;
  final String descricao;
  final String? descricaoNota;
  final String? codigoFiscal;
  final String? es;       // 'E' = Entrada, 'S' = Saída
  final int?    mobOrdem;

  const NaturezaOperacao({
    required this.id,
    required this.descricao,
    this.descricaoNota,
    this.codigoFiscal,
    this.es,
    this.mobOrdem,
  });

  /// Descrição amigável com CFOP quando disponível.
  String get displayName {
    if (codigoFiscal != null && codigoFiscal!.isNotEmpty) {
      return '$descricao ($codigoFiscal)';
    }
    return descricao;
  }

  factory NaturezaOperacao.fromMap(Map<String, dynamic> map) {
    return NaturezaOperacao(
      id:            (map['id'] ?? map['natureza_id'])?.toString() ?? '',
      descricao:     (map['descricao'] as String? ?? '').trim(),
      descricaoNota: map['descricao_nota'] as String?,
      codigoFiscal:  map['codigo_fiscal'] as String?,
      es:            map['es'] as String?,
      mobOrdem:      _toInt(map['mob_ordem']),
    );
  }

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    return int.tryParse(v.toString());
  }

  Map<String, dynamic> toMap() => {
    'natureza_id':   id,
    'descricao':     descricao,
    'descricao_nota': descricaoNota,
    'codigo_fiscal': codigoFiscal,
    'es':            es,
    'mob_ordem':     mobOrdem,
  };

  @override
  String toString() => displayName;

  @override
  bool operator ==(Object other) => other is NaturezaOperacao && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

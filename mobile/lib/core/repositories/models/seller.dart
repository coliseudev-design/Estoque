/// Seller — Vendedor sincronizado do ERP (FUNCIONARIOS WHERE MOB_ACESSO=1).
///
/// O campo [pin] corresponde ao MOB_SENHA do Firebird.
/// É armazenado no SQLite local para validação offline do PIN.
///
/// Rule-03: sellerId nunca é parâmetro livre — vem sempre da sessão ativa.
library;

class Seller {
  final String id;           // ID_FUNCIONARIO
  final String? mobileId;   // ID_MOBILE
  final String name;         // NOME
  final String? email;       // EMAIL
  final String? pin;         // MOB_SENHA (PIN de acesso mobile)
  final double? maxDiscount; // DESCONTO_MAX
  final double? commission;  // COMISSAO
  final String? lastSyncedAt;

  const Seller({
    required this.id,
    this.mobileId,
    required this.name,
    this.email,
    this.pin,
    this.maxDiscount,
    this.commission,
    this.lastSyncedAt,
  });

  /// Constrói a partir do Map retornado pelo SQLite local.
  factory Seller.fromMap(Map<String, dynamic> map) => Seller(
    id:           map['id'].toString(),
    mobileId:     map['mobile_id'] as String?,
    name:         map['name'] as String,
    email:        map['email'] as String?,
    pin:          map['pin'] as String?,
    maxDiscount:  (map['max_discount'] as num?)?.toDouble(),
    commission:   (map['commission'] as num?)?.toDouble(),
    lastSyncedAt: map['last_synced_at'] as String?,
  );

  /// Constrói a partir da resposta JSON do middleware (node-firebird → UPPERCASE).
  factory Seller.fromApi(Map<String, dynamic> json) => Seller(
    id:          json['ID'].toString(),
    mobileId:    json['MOBILEID']?.toString(),
    name:        (json['NAME'] as String? ?? '').trim(),
    email:       (json['EMAIL'] as String?)?.trim(),
    pin:         json['PASSWORDHASH'] as String?,
    maxDiscount: (json['MAXDISCOUNT'] as num?)?.toDouble(),
    commission:  (json['COMMISSIONRATE'] as num?)?.toDouble(),
  );

  Map<String, dynamic> toMap() => {
    'id':             id,
    'mobile_id':      mobileId,
    'name':           name,
    'email':          email,
    'pin':            pin,
    'max_discount':   maxDiscount,
    'commission':     commission,
    'last_synced_at': lastSyncedAt,
  };
}

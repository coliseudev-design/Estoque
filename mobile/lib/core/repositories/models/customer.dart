/// Customer — Modelo de cliente do ERP.
///
/// Sincronizado do Firebird via GET /api/sync/customers.
/// Armazenado no cache SQLite local para acesso offline.
library;

// ─────────────────────────────────────────────────────────────────────────────
// Customer
// ─────────────────────────────────────────────────────────────────────────────

class Customer {
  final String id;
  final String name;
  final String? cnpj;
  final String? city;
  final String? state;
  final double creditLimit;
  final String? lastSyncedAt;
  final String? sellerId;

  /// ID da tabela de preço vinculada ao cliente (CLIENTES.ID_TABELA).
  /// null = cliente sem tabela de preço especial.
  final String? priceTableId;

  // Contato
  final String? phone;
  final String? email;

  // Endereço completo
  final String? street;
  final String? streetNumber;
  final String? neighborhood;
  final String? zipCode;

  const Customer({
    required this.id,
    required this.name,
    this.cnpj,
    this.city,
    this.state,
    required this.creditLimit,
    this.lastSyncedAt,
    this.sellerId,
    this.priceTableId,
    this.phone,
    this.email,
    this.street,
    this.streetNumber,
    this.neighborhood,
    this.zipCode,
  });

  /// Endereço formatado para exibição na lista (cidade/UF ou vazio).
  String get location {
    if (city != null && state != null) return '$city/$state';
    if (city != null) return city!;
    if (state != null) return state!;
    return '';
  }

  /// Endereço completo formatado para o detalhe do cliente.
  String get fullAddress {
    final parts = <String>[];
    if (street != null && street!.isNotEmpty) {
      parts.add(streetNumber != null && streetNumber!.isNotEmpty
          ? '${street!}, ${streetNumber!}'
          : street!);
    }
    if (neighborhood != null && neighborhood!.isNotEmpty) {
      parts.add(neighborhood!);
    }
    if (city != null && city!.isNotEmpty) {
      parts.add(state != null && state!.isNotEmpty
          ? '${city!} - ${state!}'
          : city!);
    }
    if (zipCode != null && zipCode!.isNotEmpty) {
      parts.add('CEP ${zipCode!}');
    }
    return parts.join(', ');
  }

  factory Customer.fromMap(Map<String, dynamic> map) => Customer(
    // id e name podem vir como int do Firebird — toString() é seguro
    id:           (map['id'] ?? '').toString(),
    name:         (map['name'] ?? '').toString(),
    cnpj:         map['cnpj']?.toString(),
    city:         map['city']?.toString(),
    state:        map['state']?.toString(),
    creditLimit:  (map['credit_limit'] as num? ?? 0).toDouble(),
    lastSyncedAt: map['last_synced_at']?.toString(),
    sellerId:     map['seller_id']?.toString(),
    priceTableId: map['price_table_id']?.toString(),
    phone:        map['phone']?.toString(),
    email:        map['email']?.toString(),
    street:       map['street']?.toString(),
    streetNumber: map['street_number']?.toString(),
    neighborhood: map['neighborhood']?.toString(),
    zipCode:      map['zip_code']?.toString(),
  );

  Map<String, dynamic> toMap() => {
    'id':             id,
    'name':           name,
    'cnpj':           cnpj,
    'city':           city,
    'state':          state,
    'credit_limit':   creditLimit,
    'last_synced_at': lastSyncedAt,
    'seller_id':      sellerId,
    'price_table_id': priceTableId,
    'phone':          phone,
    'email':          email,
    'street':         street,
    'street_number':  streetNumber,
    'neighborhood':   neighborhood,
    'zip_code':       zipCode,
  };

  /// Cria uma cópia com campos seletivamente substituídos.
  Customer copyWith({
    String?  id,
    String?  name,
    String?  cnpj,
    String?  city,
    String?  state,
    double?  creditLimit,
    String?  lastSyncedAt,
    String?  sellerId,
    String?  priceTableId,
    String?  phone,
    String?  email,
    String?  street,
    String?  streetNumber,
    String?  neighborhood,
    String?  zipCode,
  }) => Customer(
    id:           id           ?? this.id,
    name:         name         ?? this.name,
    cnpj:         cnpj         ?? this.cnpj,
    city:         city         ?? this.city,
    state:        state        ?? this.state,
    creditLimit:  creditLimit  ?? this.creditLimit,
    lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    sellerId:     sellerId     ?? this.sellerId,
    priceTableId: priceTableId ?? this.priceTableId,
    phone:        phone        ?? this.phone,
    email:        email        ?? this.email,
    street:       street       ?? this.street,
    streetNumber: streetNumber ?? this.streetNumber,
    neighborhood: neighborhood ?? this.neighborhood,
    zipCode:      zipCode      ?? this.zipCode,
  );
}

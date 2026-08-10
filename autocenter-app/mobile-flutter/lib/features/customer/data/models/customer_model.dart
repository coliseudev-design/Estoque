class CustomerModel {
  final int? id;
  final int? erpId; // Nullable to support offline registration before sync
  final String? localId; // Temporary client-side identifier e.g. local_12345
  final String name;
  final String? fantasyName;
  final String? cpfCnpj;
  final String? phone;
  final String? phone2;
  final String? email;
  final String? city;
  final String? address;
  final String? street;
  final String? number;
  final String? complement;
  final String? neighborhood;
  final String? zip;
  final String? state;
  final bool active;
  final String syncStatus; // 'synced', 'pending', 'error'

  CustomerModel({
    this.id,
    this.erpId,
    this.localId,
    required this.name,
    this.fantasyName,
    this.cpfCnpj,
    this.phone,
    this.phone2,
    this.email,
    this.city,
    this.address,
    this.street,
    this.number,
    this.complement,
    this.neighborhood,
    this.zip,
    this.state,
    this.active = true,
    this.syncStatus = 'synced',
  });

  factory CustomerModel.fromJson(Map<String, dynamic> json) {
    return CustomerModel(
      id: json['id'] as int?,
      erpId: json['erpId'] as int? ?? json['erp_id'] as int?,
      localId: json['localId'] as String? ?? json['local_id'] as String?,
      name: json['name'] as String,
      fantasyName: json['fantasyName'] as String? ?? json['fantasy_name'] as String?,
      cpfCnpj: json['cpfCnpj'] as String? ?? json['cpf_cnpj'] as String?,
      phone: json['phone'] as String?,
      phone2: json['phone2'] as String?,
      email: json['email'] as String?,
      city: json['city'] as String?,
      address: json['address'] as String?,
      street: json['street'] as String?,
      number: json['number'] as String?,
      complement: json['complement'] as String?,
      neighborhood: json['neighborhood'] as String?,
      zip: json['zip'] as String?,
      state: json['state'] as String?,
      active: json['active'] == 1 || json['active'] == true,
      syncStatus: json['syncStatus'] as String? ?? json['sync_status'] as String? ?? 'synced',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'erp_id': erpId,
      'local_id': localId,
      'name': name,
      'fantasy_name': fantasyName,
      'cpf_cnpj': cpfCnpj,
      'phone': phone,
      'phone2': phone2,
      'email': email,
      'city': city,
      'address': address,
      'street': street,
      'number': number,
      'complement': complement,
      'neighborhood': neighborhood,
      'zip': zip,
      'state': state,
      'active': active ? 1 : 0,
      'sync_status': syncStatus,
    };
  }

  factory CustomerModel.fromSqlMap(Map<String, dynamic> map) {
    return CustomerModel(
      id: map['id'] as int?,
      erpId: map['erp_id'] as int?,
      localId: map['local_id'] as String?,
      name: map['name'] as String,
      fantasyName: map['fantasy_name'] as String?,
      cpfCnpj: map['cpf_cnpj'] as String?,
      phone: map['phone'] as String?,
      phone2: map['phone2'] as String?,
      email: map['email'] as String?,
      city: map['city'] as String?,
      address: map['address'] as String?,
      street: map['street'] as String?,
      number: map['number'] as String?,
      complement: map['complement'] as String?,
      neighborhood: map['neighborhood'] as String?,
      zip: map['zip'] as String?,
      state: map['state'] as String?,
      active: map['active'] == 1,
      syncStatus: map['sync_status'] as String? ?? 'synced',
    );
  }

  CustomerModel copyWith({
    int? id,
    int? erpId,
    String? localId,
    String? name,
    String? fantasyName,
    String? cpfCnpj,
    String? phone,
    String? phone2,
    String? email,
    String? city,
    String? address,
    String? street,
    String? number,
    String? complement,
    String? neighborhood,
    String? zip,
    String? state,
    bool? active,
    String? syncStatus,
  }) {
    return CustomerModel(
      id: id ?? this.id,
      erpId: erpId ?? this.erpId,
      localId: localId ?? this.localId,
      name: name ?? this.name,
      fantasyName: fantasyName ?? this.fantasyName,
      cpfCnpj: cpfCnpj ?? this.cpfCnpj,
      phone: phone ?? this.phone,
      phone2: phone2 ?? this.phone2,
      email: email ?? this.email,
      city: city ?? this.city,
      address: address ?? this.address,
      street: street ?? this.street,
      number: number ?? this.number,
      complement: complement ?? this.complement,
      neighborhood: neighborhood ?? this.neighborhood,
      zip: zip ?? this.zip,
      state: state ?? this.state,
      active: active ?? this.active,
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }
}

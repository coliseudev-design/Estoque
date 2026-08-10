class SellerModel {
  final int id;
  final String name;
  final String? email;
  final String? pin;
  final double? maxDiscount;
  final double? commissionRate;
  final bool active;

  SellerModel({
    required this.id,
    required this.name,
    this.email,
    this.pin,
    this.maxDiscount,
    this.commissionRate,
    this.active = true,
  });

  factory SellerModel.fromMap(Map<String, dynamic> map) {
    double? parseDouble(dynamic val) {
      if (val == null) return null;
      if (val is num) return val.toDouble();
      if (val is String) return double.tryParse(val);
      return null;
    }

    return SellerModel(
      id: map['id'] is int ? map['id'] : int.parse(map['id'].toString()),
      name: map['name'] ?? '',
      email: map['email'],
      pin: map['pin'] ?? map['passwordHash'] ?? map['password_hash'],
      maxDiscount: parseDouble(map['maxDiscount']) ?? parseDouble(map['max_discount']),
      commissionRate: parseDouble(map['commissionRate']) ?? parseDouble(map['commission_rate']),
      active: map['active'] == 1 || map['active'] == true || map['active'] == '1',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'pin': pin,
      'max_discount': maxDiscount,
      'active': active ? 1 : 0,
    };
  }
}

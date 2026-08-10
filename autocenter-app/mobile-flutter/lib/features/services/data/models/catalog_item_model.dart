class CatalogItemModel {
  final int erpId;
  final String name;
  final String category;
  final double price;
  final String? brand;
  final String? code;
  final bool active;

  CatalogItemModel({
    required this.erpId,
    required this.name,
    required this.category,
    required this.price,
    this.brand,
    this.code,
    required this.active,
  });

  factory CatalogItemModel.fromMap(Map<String, dynamic> map) {
    return CatalogItemModel(
      erpId: map['erp_id'] ?? map['erpId'] ?? 0,
      name: map['name'] ?? '',
      category: map['category'] ?? 'Geral',
      price: map['price'] is num
          ? (map['price'] as num).toDouble()
          : double.tryParse(map['price']?.toString() ?? '') ?? 0.0,
      brand: map['brand'],
      code: map['code'],
      active: map['active'] == 1 || map['active'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'erp_id': erpId,
      'name': name,
      'category': category,
      'price': price,
      'brand': brand,
      'code': code,
      'active': active ? 1 : 0,
    };
  }
}

class Draft {
  final int? id;
  final String vehiclePlate;
  final String? customerName;
  final String status;
  final String createdAt;

  Draft({
    this.id,
    required this.vehiclePlate,
    this.customerName,
    required this.status,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'vehicle_plate': vehiclePlate,
      'customer_name': customerName ?? 'Não Identificado',
      'status': status,
      'created_at': createdAt,
    };
  }
}

class DraftPhoto {
  final int? id;
  final int draftId;
  final String path;
  final String type; // ex: 'FRENTE', 'LATERAL_ESQ'

  DraftPhoto({
    this.id,
    required this.draftId,
    required this.path,
    required this.type,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'draft_id': draftId,
      'path': path,
      'type': type,
    };
  }
}

class DraftItem {
  final int? id;
  final int draftId;
  final String productCode;
  final String productName;
  final double quantity;
  final double unitPrice;
  final double discount;

  DraftItem({
    this.id,
    required this.draftId,
    required this.productCode,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.discount,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'draft_id': draftId,
      'product_code': productCode,
      'product_name': productName,
      'quantity': quantity,
      'unit_price': unitPrice,
      'discount': discount,
    };
  }
}

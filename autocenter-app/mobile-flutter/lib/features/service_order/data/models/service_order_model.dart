import '../../domain/entities/service_order.dart';

class ServiceOrderModel extends ServiceOrder {
  ServiceOrderModel({
    required super.id,
    super.quoteId,
    required super.deviceId,
    required super.plate,
    super.customerId,
    super.customerName,
    super.customerPhone,
    super.status,
    super.totalAmount,
    super.observation,
    required super.createdAt,
    required super.updatedAt,
    super.syncStatus,
    super.sellerId,
    super.naturezaId,
    super.paymentConditionId,
    super.paymentSpeciesId,
    super.driver,
    super.odometer,
    super.fuelLevel,
    super.items,
    super.photos,
    super.checklist,
  });

  factory ServiceOrderModel.fromEntity(ServiceOrder entity) {
    return ServiceOrderModel(
      id: entity.id,
      quoteId: entity.quoteId,
      deviceId: entity.deviceId,
      plate: entity.plate,
      customerId: entity.customerId,
      customerName: entity.customerName,
      customerPhone: entity.customerPhone,
      status: entity.status,
      totalAmount: entity.totalAmount,
      observation: entity.observation,
      createdAt: entity.createdAt,
      updatedAt: entity.updatedAt,
      syncStatus: entity.syncStatus,
      sellerId: entity.sellerId,
      naturezaId: entity.naturezaId,
      paymentConditionId: entity.paymentConditionId,
      paymentSpeciesId: entity.paymentSpeciesId,
      driver: entity.driver,
      odometer: entity.odometer,
      fuelLevel: entity.fuelLevel,
      items: entity.items,
      photos: entity.photos,
      checklist: entity.checklist,
    );
  }

  factory ServiceOrderModel.fromJson(Map<String, dynamic> json) {
    var itemsList = json['items'] as List? ?? [];
    var photosList = json['photos'] as List? ?? [];
    var checklistList = json['checklist'] as List? ?? [];

    return ServiceOrderModel(
      id: json['id'] as String,
      quoteId: json['quoteId'] as String? ?? json['quote_id'] as String?,
      deviceId: json['deviceId'] as String? ?? json['device_id'] as String? ?? '',
      plate: json['plate'] as String,
      customerId: json['customerId'] as int? ?? json['customer_id'] as int?,
      customerName: json['customerName'] as String? ?? json['customer_name'] as String?,
      customerPhone: json['customerPhone'] as String? ?? json['customer_phone'] as String?,
      status: json['status'] as String? ?? 'ABERTA',
      totalAmount: (json['totalAmount'] as num? ?? json['total_amount'] as num?)?.toDouble() ?? 0.0,
      observation: json['observation'] as String?,
      createdAt: json['createdAt'] as String? ?? json['created_at'] as String? ?? DateTime.now().toIso8601String(),
      updatedAt: json['updatedAt'] as String? ?? json['updated_at'] as String? ?? DateTime.now().toIso8601String(),
      syncStatus: json['syncStatus'] as String? ?? json['sync_status'] as String? ?? 'synced',
      sellerId: json['sellerId'] as int? ?? json['seller_id'] as int?,
      naturezaId: json['naturezaId'] as String? ?? json['natureza_id'] as String?,
      paymentConditionId: json['paymentConditionId'] as String? ?? json['payment_condition_id'] as String?,
      paymentSpeciesId: json['paymentSpeciesId'] as String? ?? json['payment_species_id'] as String?,
      driver: json['driver'] as String? ?? json['motorista'] as String?,
      odometer: (json['odometer'] as num? ?? json['km_veiculo'] as num? ?? json['odometro'] as num?)?.toDouble(),
      fuelLevel: (json['fuelLevel'] as num? ?? json['fuel_level'] as num? ?? json['combustivel_nivel'] as num?)?.toDouble(),
      items: itemsList.map((i) => ServiceOrderItemModel.fromJson(i as Map<String, dynamic>)).toList(),
      photos: photosList.map((p) => ServiceOrderPhotoModel.fromJson(p as Map<String, dynamic>)).toList(),
      checklist: checklistList.map((c) => ServiceOrderChecklistModel.fromJson(c as Map<String, dynamic>)).toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'quoteId': quoteId,
      'quote_id': quoteId,
      'deviceId': deviceId,
      'device_id': deviceId,
      'plate': plate,
      'customerId': customerId,
      'customer_id': customerId,
      'customerName': customerName,
      'customer_name': customerName,
      'customerPhone': customerPhone,
      'customer_phone': customerPhone,
      'status': status,
      'totalAmount': totalAmount,
      'total_amount': totalAmount,
      'observation': observation,
      'createdAt': createdAt,
      'created_at': createdAt,
      'updatedAt': updatedAt,
      'updated_at': updatedAt,
      'sellerId': sellerId,
      'seller_id': sellerId,
      'naturezaId': naturezaId,
      'natureza_id': naturezaId,
      'paymentConditionId': paymentConditionId,
      'payment_condition_id': paymentConditionId,
      'paymentSpeciesId': paymentSpeciesId,
      'payment_species_id': paymentSpeciesId,
      'driver': driver,
      'motorista': driver,
      'odometer': odometer,
      'km_veiculo': odometer,
      'fuelLevel': fuelLevel,
      'fuel_level': fuelLevel,
      'items': items.map((i) => ServiceOrderItemModel.fromEntity(i).toJson()).toList(),
      'photos': photos.map((p) => ServiceOrderPhotoModel.fromEntity(p).toJson()).toList(),
      'checklist': checklist.map((c) => ServiceOrderChecklistModel.fromEntity(c).toJson()).toList(),
    };
  }

  factory ServiceOrderModel.fromSqlMap(Map<String, dynamic> map, {
    List<ServiceOrderItem> items = const [],
    List<ServiceOrderPhoto> photos = const [],
    List<ServiceOrderChecklist> checklist = const [],
  }) {
    return ServiceOrderModel(
      id: map['id'] as String,
      quoteId: map['quote_id'] as String?,
      deviceId: map['device_id'] as String,
      plate: map['plate'] as String,
      customerId: map['customer_id'] as int?,
      customerName: map['customer_name'] as String?,
      customerPhone: map['customer_phone'] as String?,
      status: map['status'] as String? ?? 'ABERTA',
      totalAmount: (map['total_amount'] as num?)?.toDouble() ?? 0.0,
      observation: map['observation'] as String?,
      createdAt: map['created_at'] as String,
      updatedAt: map['updated_at'] as String,
      syncStatus: map['sync_status'] as String? ?? 'synced',
      sellerId: map['seller_id'] as int?,
      naturezaId: map['natureza_id'] as String?,
      paymentConditionId: map['payment_condition_id'] as String?,
      paymentSpeciesId: map['payment_species_id'] as String?,
      driver: map['driver'] as String?,
      odometer: (map['odometer'] as num?)?.toDouble(),
      fuelLevel: (map['fuel_level'] as num?)?.toDouble(),
      items: items,
      photos: photos,
      checklist: checklist,
    );
  }

  Map<String, dynamic> toSqlMap() {
    return {
      'id': id,
      'quote_id': quoteId,
      'device_id': deviceId,
      'plate': plate,
      'customer_id': customerId,
      'customer_name': customerName,
      'customer_phone': customerPhone,
      'status': status,
      'total_amount': totalAmount,
      'observation': observation,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'sync_status': syncStatus,
      'seller_id': sellerId,
      'natureza_id': naturezaId,
      'payment_condition_id': paymentConditionId,
      'payment_species_id': paymentSpeciesId,
      'driver': driver,
      'odometer': odometer,
      'fuel_level': fuelLevel,
    };
  }
}

class ServiceOrderItemModel extends ServiceOrderItem {
  ServiceOrderItemModel({
    required super.id,
    required super.serviceOrderId,
    required super.productCode,
    required super.productDescription,
    required super.quantity,
    required super.unitPrice,
    required super.totalPrice,
    super.itemType,
    super.technicianId,
    required super.createdAt,
  });

  factory ServiceOrderItemModel.fromEntity(ServiceOrderItem entity) {
    return ServiceOrderItemModel(
      id: entity.id,
      serviceOrderId: entity.serviceOrderId,
      productCode: entity.productCode,
      productDescription: entity.productDescription,
      quantity: entity.quantity,
      unitPrice: entity.unitPrice,
      totalPrice: entity.totalPrice,
      itemType: entity.itemType,
      technicianId: entity.technicianId,
      createdAt: entity.createdAt,
    );
  }

  factory ServiceOrderItemModel.fromJson(Map<String, dynamic> json) {
    return ServiceOrderItemModel(
      id: json['id'] as String? ?? '',
      serviceOrderId: json['serviceOrderId'] as String? ?? json['service_order_id'] as String? ?? '',
      productCode: json['productCode'] as String? ?? json['product_code'] as String? ?? '',
      productDescription: json['productDescription'] as String? ?? json['product_description'] as String? ?? '',
      quantity: (json['quantity'] as num?)?.toDouble() ?? 0.0,
      unitPrice: (json['unitPrice'] as num?)?.toDouble() ?? 0.0,
      totalPrice: (json['totalPrice'] as num?)?.toDouble() ?? 0.0,
      itemType: json['itemType'] as String? ?? json['item_type'] as String? ?? 'PART',
      technicianId: json['technicianId'] as int? ?? json['technician_id'] as int?,
      createdAt: json['createdAt'] as String? ?? json['created_at'] as String? ?? DateTime.now().toIso8601String(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'serviceOrderId': serviceOrderId,
      'service_order_id': serviceOrderId,
      'productCode': productCode,
      'product_code': productCode,
      'productDescription': productDescription,
      'product_description': productDescription,
      'quantity': quantity,
      'unitPrice': unitPrice,
      'unit_price': unitPrice,
      'totalPrice': totalPrice,
      'total_price': totalPrice,
      'itemType': itemType,
      'item_type': itemType,
      'technicianId': technicianId,
      'technician_id': technicianId,
    };
  }

  factory ServiceOrderItemModel.fromSqlMap(Map<String, dynamic> map) {
    return ServiceOrderItemModel(
      id: map['id'] as String,
      serviceOrderId: map['service_order_id'] as String,
      productCode: map['product_code'] as String,
      productDescription: map['product_description'] as String,
      quantity: (map['quantity'] as num).toDouble(),
      unitPrice: (map['unit_price'] as num).toDouble(),
      totalPrice: (map['total_price'] as num).toDouble(),
      itemType: map['item_type'] as String? ?? 'PART',
      technicianId: map['technician_id'] as int?,
      createdAt: map['created_at'] as String,
    );
  }

  Map<String, dynamic> toSqlMap() {
    return {
      'id': id,
      'service_order_id': serviceOrderId,
      'product_code': productCode,
      'product_description': productDescription,
      'quantity': quantity,
      'unit_price': unitPrice,
      'total_price': totalPrice,
      'item_type': itemType,
      'technician_id': technicianId,
      'created_at': createdAt,
    };
  }
}

class ServiceOrderPhotoModel extends ServiceOrderPhoto {
  ServiceOrderPhotoModel({
    required super.id,
    required super.serviceOrderId,
    required super.photoUrl,
    super.photoType,
    required super.createdAt,
  });

  factory ServiceOrderPhotoModel.fromEntity(ServiceOrderPhoto entity) {
    return ServiceOrderPhotoModel(
      id: entity.id,
      serviceOrderId: entity.serviceOrderId,
      photoUrl: entity.photoUrl,
      photoType: entity.photoType,
      createdAt: entity.createdAt,
    );
  }

  factory ServiceOrderPhotoModel.fromJson(Map<String, dynamic> json) {
    return ServiceOrderPhotoModel(
      id: json['id'] as String? ?? '',
      serviceOrderId: json['serviceOrderId'] as String? ?? json['service_order_id'] as String? ?? '',
      photoUrl: json['photoUrl'] as String? ?? json['photo_url'] as String? ?? '',
      photoType: json['photoType'] as String? ?? json['photo_type'] as String?,
      createdAt: json['createdAt'] as String? ?? json['created_at'] as String? ?? DateTime.now().toIso8601String(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'serviceOrderId': serviceOrderId,
      'service_order_id': serviceOrderId,
      'photoUrl': photoUrl,
      'photo_url': photoUrl,
      'photoType': photoType,
      'photo_type': photoType,
    };
  }

  factory ServiceOrderPhotoModel.fromSqlMap(Map<String, dynamic> map) {
    return ServiceOrderPhotoModel(
      id: map['id'] as String,
      serviceOrderId: map['service_order_id'] as String,
      photoUrl: map['photo_url'] as String,
      photoType: map['photo_type'] as String?,
      createdAt: map['created_at'] as String,
    );
  }

  Map<String, dynamic> toSqlMap() {
    return {
      'id': id,
      'service_order_id': serviceOrderId,
      'photo_url': photoUrl,
      'photo_type': photoType,
      'created_at': createdAt,
    };
  }
}

class ServiceOrderChecklistModel extends ServiceOrderChecklist {
  ServiceOrderChecklistModel({
    required super.id,
    required super.serviceOrderId,
    required super.itemName,
    required super.status,
    super.observation,
    required super.createdAt,
    required super.updatedAt,
  });

  factory ServiceOrderChecklistModel.fromEntity(ServiceOrderChecklist entity) {
    return ServiceOrderChecklistModel(
      id: entity.id,
      serviceOrderId: entity.serviceOrderId,
      itemName: entity.itemName,
      status: entity.status,
      observation: entity.observation,
      createdAt: entity.createdAt,
      updatedAt: entity.updatedAt,
    );
  }

  factory ServiceOrderChecklistModel.fromJson(Map<String, dynamic> json) {
    return ServiceOrderChecklistModel(
      id: json['id'] as String? ?? '',
      serviceOrderId: json['serviceOrderId'] as String? ?? json['service_order_id'] as String? ?? '',
      itemName: json['itemName'] as String? ?? json['item_name'] as String? ?? '',
      status: json['status'] as String? ?? 'OK',
      observation: json['observation'] as String?,
      createdAt: json['createdAt'] as String? ?? json['created_at'] as String? ?? DateTime.now().toIso8601String(),
      updatedAt: json['updatedAt'] as String? ?? json['updated_at'] as String? ?? DateTime.now().toIso8601String(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'serviceOrderId': serviceOrderId,
      'service_order_id': serviceOrderId,
      'itemName': itemName,
      'item_name': itemName,
      'status': status,
      'observation': observation,
    };
  }

  factory ServiceOrderChecklistModel.fromSqlMap(Map<String, dynamic> map) {
    return ServiceOrderChecklistModel(
      id: map['id'] as String,
      serviceOrderId: map['service_order_id'] as String,
      itemName: map['item_name'] as String,
      status: map['status'] as String,
      observation: map['observation'] as String?,
      createdAt: map['created_at'] as String,
      updatedAt: map['updated_at'] as String,
    );
  }

  Map<String, dynamic> toSqlMap() {
    return {
      'id': id,
      'service_order_id': serviceOrderId,
      'item_name': itemName,
      'status': status,
      'observation': observation,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }
}

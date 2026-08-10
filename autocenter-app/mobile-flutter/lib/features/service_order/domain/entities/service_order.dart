class ServiceOrder {
  final String id;
  final String? quoteId;
  final String deviceId;
  final String plate;
  final int? customerId;
  final String? customerName;
  final String? customerPhone;
  final String status;
  final double totalAmount;
  final String? observation;
  final String createdAt;
  final String updatedAt;
  final String syncStatus; // 'synced', 'pending', 'error'
  final int? sellerId;
  final String? naturezaId;
  final String? paymentConditionId;
  final String? paymentSpeciesId;
  final String? driver;
  final double? odometer;
  final double? fuelLevel;
  final List<ServiceOrderItem> items;
  final List<ServiceOrderPhoto> photos;
  final List<ServiceOrderChecklist> checklist;

  ServiceOrder({
    required this.id,
    this.quoteId,
    required this.deviceId,
    required this.plate,
    this.customerId,
    this.customerName,
    this.customerPhone,
    this.status = 'ABERTA',
    this.totalAmount = 0.0,
    this.observation,
    required this.createdAt,
    required this.updatedAt,
    this.syncStatus = 'synced',
    this.sellerId,
    this.naturezaId,
    this.paymentConditionId,
    this.paymentSpeciesId,
    this.driver,
    this.odometer,
    this.fuelLevel,
    this.items = const [],
    this.photos = const [],
    this.checklist = const [],
  });

  ServiceOrder copyWith({
    String? id,
    String? quoteId,
    String? deviceId,
    String? plate,
    int? customerId,
    String? customerName,
    String? customerPhone,
    String? status,
    double? totalAmount,
    String? observation,
    String? createdAt,
    String? updatedAt,
    String? syncStatus,
    int? sellerId,
    String? naturezaId,
    String? paymentConditionId,
    String? paymentSpeciesId,
    String? driver,
    double? odometer,
    double? fuelLevel,
    List<ServiceOrderItem>? items,
    List<ServiceOrderPhoto>? photos,
    List<ServiceOrderChecklist>? checklist,
  }) {
    return ServiceOrder(
      id: id ?? this.id,
      quoteId: quoteId ?? this.quoteId,
      deviceId: deviceId ?? this.deviceId,
      plate: plate ?? this.plate,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      status: status ?? this.status,
      totalAmount: totalAmount ?? this.totalAmount,
      observation: observation ?? this.observation,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      sellerId: sellerId ?? this.sellerId,
      naturezaId: naturezaId ?? this.naturezaId,
      paymentConditionId: paymentConditionId ?? this.paymentConditionId,
      paymentSpeciesId: paymentSpeciesId ?? this.paymentSpeciesId,
      driver: driver ?? this.driver,
      odometer: odometer ?? this.odometer,
      fuelLevel: fuelLevel ?? this.fuelLevel,
      items: items ?? this.items,
      photos: photos ?? this.photos,
      checklist: checklist ?? this.checklist,
    );
  }
}

class ServiceOrderItem {
  final String id;
  final String serviceOrderId;
  final String productCode;
  final String productDescription;
  final double quantity;
  final double unitPrice;
  final double totalPrice;
  final String itemType; // 'PART', 'SERVICE'
  final int? technicianId;
  final String createdAt;

  ServiceOrderItem({
    required this.id,
    required this.serviceOrderId,
    required this.productCode,
    required this.productDescription,
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
    this.itemType = 'PART',
    this.technicianId,
    required this.createdAt,
  });

  ServiceOrderItem copyWith({
    String? id,
    String? serviceOrderId,
    String? productCode,
    String? productDescription,
    double? quantity,
    double? unitPrice,
    double? totalPrice,
    String? itemType,
    int? technicianId,
    String? createdAt,
  }) {
    return ServiceOrderItem(
      id: id ?? this.id,
      serviceOrderId: serviceOrderId ?? this.serviceOrderId,
      productCode: productCode ?? this.productCode,
      productDescription: productDescription ?? this.productDescription,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      totalPrice: totalPrice ?? this.totalPrice,
      itemType: itemType ?? this.itemType,
      technicianId: technicianId ?? this.technicianId,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

class ServiceOrderPhoto {
  final String id;
  final String serviceOrderId;
  final String photoUrl; // local file path when pending, remote URL when synced
  final String? photoType; // 'FRONT', 'LEFT', 'RIGHT', 'REAR', 'ODOMETER', 'DAMAGE', etc.
  final String createdAt;

  ServiceOrderPhoto({
    required this.id,
    required this.serviceOrderId,
    required this.photoUrl,
    this.photoType,
    required this.createdAt,
  });

  ServiceOrderPhoto copyWith({
    String? id,
    String? serviceOrderId,
    String? photoUrl,
    String? photoType,
    String? createdAt,
  }) {
    return ServiceOrderPhoto(
      id: id ?? this.id,
      serviceOrderId: serviceOrderId ?? this.serviceOrderId,
      photoUrl: photoUrl ?? this.photoUrl,
      photoType: photoType ?? this.photoType,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

class ServiceOrderChecklist {
  final String id;
  final String serviceOrderId;
  final String itemName;
  final String status; // 'OK', 'WARN', 'BAD'
  final String? observation;
  final String createdAt;
  final String updatedAt;

  ServiceOrderChecklist({
    required this.id,
    required this.serviceOrderId,
    required this.itemName,
    required this.status,
    this.observation,
    required this.createdAt,
    required this.updatedAt,
  });

  ServiceOrderChecklist copyWith({
    String? id,
    String? serviceOrderId,
    String? itemName,
    String? status,
    String? observation,
    String? createdAt,
    String? updatedAt,
  }) {
    return ServiceOrderChecklist(
      id: id ?? this.id,
      serviceOrderId: serviceOrderId ?? this.serviceOrderId,
      itemName: itemName ?? this.itemName,
      status: status ?? this.status,
      observation: observation ?? this.observation,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

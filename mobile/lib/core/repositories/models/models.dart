/// Modelos de domínio: Product, Order, OrderItem, CartItem.
///
/// Simples classes imutáveis — sem geração de código (Freezed) nesta fase
/// para manter a compilação simples. Freezed pode ser adicionado em refactor.
///
/// Convenções de nomenclatura (Rule-14):
/// - Nomes descritivos, sem abreviações
/// - fromMap/toMap para SQLite
/// - copyWith para imutabilidade
library;

import '../../services/discount_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Product
// ─────────────────────────────────────────────────────────────────────────────

/// Produto do catálogo local (lido do cache SQLite).
class Product {
  final String code;
  final String name;
  final String? nameShort;
  final double price;
  final double? priceMin;

  /// Preço de custo do produto (PRODUTO_PRECOS.PRECO_CUSTO).
  /// Piso absoluto de desconto — nunca vender abaixo disso.
  final double? priceCost;

  final double stock;
  final String? unit;
  final String? brand;
  final String? barCode;
  final String? reference;

  /// Desconto máximo permitido para este produto (% de 0 a 100).
  /// null = sem limite (usa limite do vendedor).
  final double? maxDiscount;

  /// Categoria do produto (CATEGORIAS.DESCRICAO do Firebird).
  final String? category;

  /// Metadado de filial: ID_DEPTO da filial padrão vindo do Worker.
  final int? erpDeptoPadrao;

  final String? lastSyncedAt;

  const Product({
    required this.code,
    required this.name,
    this.nameShort,
    required this.price,
    this.priceMin,
    this.priceCost,
    required this.stock,
    this.unit,
    this.brand,
    this.barCode,
    this.reference,
    this.maxDiscount,
    this.category,
    this.erpDeptoPadrao,
    this.lastSyncedAt,
  });

  /// Se false, botão de adicionar ao carrinho deve ser desabilitado.
  bool get isInStock => stock > 0;

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      code:         map['code'] as String,
      name:         map['name'] as String,
      nameShort:    map['name_short'] as String?,
      price:        (map['price'] as num).toDouble(),
      priceMin:     (map['price_min'] as num?)?.toDouble(),
      priceCost:    (map['price_cost'] as num?)?.toDouble(),
      stock:        (map['stock'] as num? ?? 0).toDouble(),
      unit:         map['unit'] as String?,
      brand:        map['brand'] as String?,
      barCode:      map['bar_code'] as String?,
      reference:    map['reference'] as String?,
      maxDiscount:  (map['max_discount'] as num?)?.toDouble(),
      category:     map['category'] as String?,
      erpDeptoPadrao: (map['erp_depto_padrao'] as num?)?.toInt(),
      lastSyncedAt: map['last_synced_at'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    'code':           code,
    'name':           name,
    'name_short':     nameShort,
    'price':          price,
    'price_min':      priceMin,
    'price_cost':     priceCost,
    'stock':          stock,
    'unit':           unit,
    'brand':          brand,
    'bar_code':       barCode,
    'reference':      reference,
    'max_discount':   maxDiscount,
    'category':       category,
    'erp_depto_padrao': erpDeptoPadrao,
    'last_synced_at': lastSyncedAt,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// CartItem — Item no carrinho (ainda não é um OrderItem persistido)
// ─────────────────────────────────────────────────────────────────────────────

/// Representa um item no carrinho durante a composição do pedido.
/// É volátil (em memória) até a confirmação, quando vira [OrderItem].
class CartItem {
  final Product      product;
  final double       quantity;

  /// Desconto aplicado a este item, em percentual (0 a 100), já clampado.
  final double       discount;

  /// Modo de entrada do desconto: percentual ou valor fixo (R$).
  final DiscountMode discountMode;

  /// Valor bruto digitado pelo vendedor antes do clamp (para exibição no UI).
  final double       rawDiscountInput;

  const CartItem({
    required this.product,
    required this.quantity,
    this.discount          = 0.0,
    this.discountMode      = DiscountMode.percent,
    this.rawDiscountInput  = 0.0,
  });

  /// Preço unitário já com desconto aplicado.
  double get unitPriceWithDiscount => product.price * (1 - discount / 100);

  /// Total do item: preço c/ desconto × quantidade.
  double get totalPrice => unitPriceWithDiscount * quantity;

  /// Valor absoluto do desconto deste item.
  double get discountValue => product.price * quantity - totalPrice;

  CartItem copyWith({
    double?       quantity,
    double?       discount,
    DiscountMode? discountMode,
    double?       rawDiscountInput,
  }) {
    return CartItem(
      product:          product,
      quantity:         quantity         ?? this.quantity,
      discount:         discount         ?? this.discount,
      discountMode:     discountMode     ?? this.discountMode,
      rawDiscountInput: rawDiscountInput ?? this.rawDiscountInput,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// OrderItem — Item persistido em um pedido confirmado
// ─────────────────────────────────────────────────────────────────────────────

/// Item de pedido persistido no SQLite e enviável ao Firebird.
class OrderItem {
  final String id;
  final String orderId;
  final String productCode;
  final String productName;
  final double quantity;
  final double unitPrice;
  final double discount;          // % efetivo aplicado
  final double totalPrice;
  /// Modo do desconto: 'percent' ou 'value' — restaurado na UI do cart.
  final String discountMode;
  /// Valor bruto digitado pelo vendedor (antes de converter para %).
  final double rawDiscountInput;

  const OrderItem({
    required this.id,
    required this.orderId,
    required this.productCode,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    this.discount = 0.0,
    required this.totalPrice,
    this.discountMode     = 'percent',
    this.rawDiscountInput = 0.0,
  });

  factory OrderItem.fromMap(Map<String, dynamic> map) {
    return OrderItem(
      id:               map['id'] as String,
      orderId:          map['order_id'] as String,
      productCode:      map['product_code'] as String,
      productName:      map['product_name'] as String,
      quantity:         (map['quantity'] as num).toDouble(),
      unitPrice:        (map['unit_price'] as num).toDouble(),
      discount:         (map['discount'] as num? ?? 0).toDouble(),
      totalPrice:       (map['total_price'] as num).toDouble(),
      discountMode:     map['discount_mode'] as String? ?? 'percent',
      rawDiscountInput: (map['raw_discount_input'] as num? ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toMap() => {
    'id':                 id,
    'order_id':           orderId,
    'product_code':       productCode,
    'product_name':       productName,
    'quantity':           quantity,
    'unit_price':         unitPrice,
    'discount':           discount,
    'total_price':        totalPrice,
    'discount_mode':      discountMode,
    'raw_discount_input': rawDiscountInput,
  };

  /// Payload para envio ao middleware (camelCase para Node.js).
  Map<String, dynamic> toSyncPayload() => {
    'id':               id,
    'productCode':      productCode,
    'productName':      productName,
    'quantity':         quantity,
    'unitPrice':        unitPrice,
    'discount':         discount,
    'discountPercent':  discount,
    // Valor absoluto do desconto deste item (unitPrice × qty − totalPrice),
    // calculado a partir do % efetivo já clampado pelo DiscountService.
    // Não é o rawDiscountInput (valor bruto digitado — apenas para restaurar a UI).
    'discountValue':    (unitPrice * quantity) - totalPrice,
    'discountMode':     discountMode,
    'totalPrice':       totalPrice,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Order — Pedido completo
// ─────────────────────────────────────────────────────────────────────────────

/// Enum de status de sincronização de um pedido.
/// Mapeado diretamente para a coluna `sync_status` no SQLite.
enum OrderSyncStatus {
  /// Salvo localmente — aguarda envio.
  pending,

  /// Sendo enviado ao middleware agora.
  syncing,

  /// Confirmado pelo servidor (server_confirmed_at preenchido).
  synced,

  /// Falha de sincronização — requer atenção do usuário.
  error,

  /// Orçamento local — NÃO sincroniza até ser convertido em pedido.
  draft;

  static OrderSyncStatus fromString(String? value) {
    return OrderSyncStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => OrderSyncStatus.pending,
    );
  }

  String get label => switch (this) {
    OrderSyncStatus.pending  => 'Aguardando envio',
    OrderSyncStatus.syncing  => 'Enviando...',
    OrderSyncStatus.synced   => 'Confirmado',
    OrderSyncStatus.error    => 'Erro de envio',
    OrderSyncStatus.draft    => 'Orçamento',
  };
}

/// Pedido completo com seus itens.
class Order {
  final String id;
  final String customerId;
  final String customerName;
  final double totalAmount;
  final String? notes;
  final OrderSyncStatus syncStatus;
  final String createdAt;
  final String updatedAt;
  final String? serverConfirmedAt;
  final List<OrderItem> items;

  // Campos de pagamento (adicionados na v4/12)
  final String? paymentSpeciesId;
  final String? paymentSpeciesName;
  final String? paymentConditionId;
  final String? paymentConditionName;
  final int?    paymentDays;
  final double  discountPercent;
  final double  discountValue;

  // Parcelamento — vindos de PaymentCondition (FORMA_PGTO)
  final int?    paymentInstallments;     // PARCELAS (quantas parcelas)
  final int?    paymentDaysPerInstallment; // DIAS_PARCELAS (dias entre parcelas)
  final int?    paymentEntryDays;        // DIAS_ENTRADA (dias até 1ª parcela)

  // Natureza de operação (adicionada na v4)
  final String? naturezaId;
  final String? naturezaDescricao;

  /// Mensagem de erro retornada pela VPS em caso de falha de sync.
  final String? errorMessage;

  /// Desconto global do pedido — input bruto digitado pelo vendedor.
  final double orderDiscountInput;

  /// Modo do desconto global: 'percent' ou 'value'.
  final String orderDiscountMode;

  /// Número de tentativas de sync realizadas automaticamente (backoff expon.).
  final int retryCount;

  /// ID do pedido registrado no ERP Firebird (preenchido pelo Worker após confirmar).
  /// Ex: "12345" — exibido para o vendedor como "Pedido ERP #12345".
  final String? erpOrderId;

  const Order({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.totalAmount,
    this.notes,
    required this.syncStatus,
    required this.createdAt,
    required this.updatedAt,
    this.serverConfirmedAt,
    this.items = const [],
    this.paymentSpeciesId,
    this.paymentSpeciesName,
    this.paymentConditionId,
    this.paymentConditionName,
    this.paymentDays,
    this.discountPercent = 0,
    this.discountValue   = 0,
    this.paymentInstallments,
    this.paymentDaysPerInstallment,
    this.paymentEntryDays,
    this.naturezaId,
    this.naturezaDescricao,
    this.errorMessage,
    this.orderDiscountInput = 0,
    this.orderDiscountMode  = 'percent',
    this.erpOrderId,
    this.retryCount  = 0,
  });

  bool get isSynced => syncStatus == OrderSyncStatus.synced;
  bool get hasError => syncStatus == OrderSyncStatus.error;
  bool get isPending => syncStatus == OrderSyncStatus.pending;
  bool get isDraft => syncStatus == OrderSyncStatus.draft;

  factory Order.fromMap(Map<String, dynamic> map, {List<OrderItem>? items}) {
    return Order(
      id:                  map['id'] as String,
      customerId:          map['customer_id'] as String,
      customerName:        map['customer_name'] as String,
      totalAmount:         (map['total_amount'] as num).toDouble(),
      notes:               map['notes'] as String?,
      syncStatus:          OrderSyncStatus.fromString(map['sync_status'] as String?),
      createdAt:           map['created_at'] as String,
      updatedAt:           map['updated_at'] as String,
      serverConfirmedAt:   map['server_confirmed_at'] as String?,
      items:               items ?? [],
      paymentSpeciesId:    map['payment_species_id'] as String?,
      paymentSpeciesName:  map['payment_species_name'] as String?,
      paymentConditionId:  map['payment_condition_id'] as String?,
      paymentConditionName: map['payment_condition_name'] as String?,
      paymentDays:         map['payment_days'] as int?,
      discountPercent:     (map['discount_percent'] as num? ?? 0).toDouble(),
      discountValue:       (map['discount_value'] as num? ?? 0).toDouble(),
      // BLOCKER-2 fix: casting defensivo — SQLite pode retornar tipos diferentes
      // dependendo da versão do DB (int, String ou null em v20 sem migration v21).
      paymentInstallments:      (map['payment_installments'] as num?)?.toInt(),
      paymentDaysPerInstallment: (map['payment_days_per_installment'] as num?)?.toInt(),
      paymentEntryDays:         (map['payment_entry_days'] as num?)?.toInt(),
      naturezaId:          map['natureza_id'] as String?,
      naturezaDescricao:   map['natureza_descricao'] as String?,
      errorMessage:        map['error_message'] as String?,
      orderDiscountInput:  (map['order_discount_input'] as num? ?? 0).toDouble(),
      orderDiscountMode:   map['order_discount_mode'] as String? ?? 'percent',
      erpOrderId:          map['erp_order_id'] as String?,
      retryCount:          (map['retry_count'] as int?) ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
    'id':                  id,
    'customer_id':         customerId,
    'customer_name':       customerName,
    'total_amount':        totalAmount,
    'notes':               notes,
    'sync_status':         syncStatus.name,
    'created_at':          createdAt,
    'updated_at':          updatedAt,
    'server_confirmed_at': serverConfirmedAt,
    'payment_species_id':  paymentSpeciesId,
    'payment_species_name': paymentSpeciesName,
    'payment_condition_id': paymentConditionId,
    'payment_condition_name': paymentConditionName,
    'payment_days':        paymentDays,
    'discount_percent':    discountPercent,
    'discount_value':      discountValue,
    'payment_installments':       paymentInstallments,
    'payment_days_per_installment': paymentDaysPerInstallment,
    'payment_entry_days':          paymentEntryDays,
    'natureza_id':         naturezaId,
    'natureza_descricao':  naturezaDescricao,
    'error_message':       errorMessage,
    'order_discount_input': orderDiscountInput,
    'order_discount_mode':  orderDiscountMode,
    'erp_order_id':        erpOrderId,
    'retry_count':         retryCount,
  };

  /// Payload completo para envio ao middleware → Firebird.
  Map<String, dynamic> toSyncPayload(String sellerId, String companyId) => {
    'id':               id,
    'customerId':       customerId,
    'customerName':     customerName,
    'sellerId':         sellerId,
    'companyId':        companyId,
    'totalAmount':      totalAmount,
    'notes':            notes,
    'createdAt':        createdAt,
    'updatedAt':        updatedAt,
    'paymentSpeciesId': paymentSpeciesId,
    'paymentSpeciesName': paymentSpeciesName,
    'paymentConditionId': paymentConditionId,
    'paymentConditionName': paymentConditionName,
    'paymentDays':      paymentDays ?? 0,
    'paymentInstallments':       paymentInstallments ?? 1,
    'paymentDaysPerInstallment': paymentDaysPerInstallment ?? 30,
    'paymentEntryDays':          paymentEntryDays ?? 0,
    'naturezaId':       naturezaId,
    'discountPercent':  discountPercent,
    'discountValue':    discountValue,
    'items':            items.map((i) => i.toSyncPayload()).toList(),
  };

  Order copyWith({
    OrderSyncStatus? syncStatus,
    String? notes,
    String? paymentSpeciesId,
    String? paymentSpeciesName,
    String? paymentConditionId,
    String? paymentConditionName,
    int? paymentDays,
    int? paymentInstallments,
    int? paymentDaysPerInstallment,
    int? paymentEntryDays,
    double? discountPercent,
    double? discountValue,
    double? orderDiscountInput,
    String? orderDiscountMode,
    String? naturezaId,
    String? naturezaDescricao,
  }) {
    return Order(
      id:                  id,
      customerId:          customerId,
      customerName:        customerName,
      totalAmount:         totalAmount,
      notes:               notes ?? this.notes,
      syncStatus:          syncStatus ?? this.syncStatus,
      createdAt:           createdAt,
      updatedAt:           updatedAt,
      serverConfirmedAt:   serverConfirmedAt,
      items:               items,
      paymentSpeciesId:    paymentSpeciesId ?? this.paymentSpeciesId,
      paymentSpeciesName:  paymentSpeciesName ?? this.paymentSpeciesName,
      paymentConditionId:  paymentConditionId ?? this.paymentConditionId,
      paymentConditionName: paymentConditionName ?? this.paymentConditionName,
      paymentDays:         paymentDays ?? this.paymentDays,
      paymentInstallments:       paymentInstallments ?? this.paymentInstallments,
      paymentDaysPerInstallment: paymentDaysPerInstallment ?? this.paymentDaysPerInstallment,
      paymentEntryDays:          paymentEntryDays ?? this.paymentEntryDays,
      discountPercent:     discountPercent ?? this.discountPercent,
      discountValue:       discountValue ?? this.discountValue,
      orderDiscountInput:  orderDiscountInput ?? this.orderDiscountInput,
      orderDiscountMode:   orderDiscountMode ?? this.orderDiscountMode,
      naturezaId:          naturezaId ?? this.naturezaId,
      naturezaDescricao:   naturezaDescricao ?? this.naturezaDescricao,
      errorMessage:        errorMessage,
      erpOrderId:          erpOrderId,
      retryCount:          retryCount,
    );
  }
}

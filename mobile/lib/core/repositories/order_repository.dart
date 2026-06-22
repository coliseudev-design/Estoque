/// OrderRepository — CRUD de pedidos e itens no SQLite local.
///
/// REGRA (Rule-06): Toda lógica de negócio fica no CartNotifier/Feature layer.
/// REGRA (Rule-14): Funções públicas têm docstrings completos.
library;

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../database/database_helper.dart';
import '../sync/sync_service.dart';
import 'models/models.dart';

class OrderRepository {
  final DatabaseHelper _db;
  final SyncService    _sync;

  static const _uuid = Uuid();

  OrderRepository({required DatabaseHelper db, required SyncService sync})
      : _db   = db,
        _sync = sync;

  // ─────────────────────────────────────────────────────────────────────────
  // Leitura
  // ─────────────────────────────────────────────────────────────────────────

  /// Retorna todos os pedidos com seus itens, ordenados por data decrescente.
  Future<List<Order>> getAll({required String companyId}) async {
    final database  = await _db.database;
    final orderRows = await _db.getAllOrders(companyId);
    if (orderRows.isEmpty) return [];

    final orderIds     = orderRows.map((r) => r['id'] as String).toList();
    final placeholders = List.filled(orderIds.length, '?').join(',');

    final itemRows = await database.query(
      'order_items',
      where: 'order_id IN ($placeholders)',
      whereArgs: orderIds,
    );

    final itemsByOrder = <String, List<OrderItem>>{};
    for (final row in itemRows) {
      final item = OrderItem.fromMap(row);
      itemsByOrder.putIfAbsent(item.orderId, () => []).add(item);
    }

    return orderRows.map((row) {
      final id = row['id'] as String;
      return Order.fromMap(row, items: itemsByOrder[id] ?? []);
    }).toList();
  }

  /// Retorna um pedido específico por [id] com seus itens.
  Future<Order?> getById(String id) async {
    final database = await _db.database;
    final rows     = await database.query(
      'orders',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;

    final itemRows = await database.query(
      'order_items',
      where: 'order_id = ?',
      whereArgs: [id],
    );
    final items = itemRows.map(OrderItem.fromMap).toList();
    return Order.fromMap(rows.first, items: items);
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Histórico filtrado
  // ───────────────────────────────────────────────────────────────────────────

  /// Retorna pedidos filtrados por período e/ou texto de cliente, com seus itens.
  ///
  /// @param from    Data de início do período (inclusive). Null = sem limite.
  /// @param to      Data de fim do período (inclusive, vai até 23:59:59). Null = sem limite.
  /// @param search  Texto para filtrar por nome do cliente (case-insensitive).
  /// @returns       Pedidos ordenados por `created_at` decrescente.
  Future<List<Order>> getHistory({
    required String companyId,
    DateTime? from,
    DateTime? to,
    String?   search,
  }) async {
    final database = await _db.database;

    final where     = <String>['company_id = ?'];
    final whereArgs = <dynamic>[companyId];

    if (from != null) {
      where.add('created_at >= ?');
      whereArgs.add(from.toIso8601String());
    }
    if (to != null) {
      // Inclui o dia inteiro: vai até 23:59:59.999 da data 'to'
      final endOfDay = DateTime(to.year, to.month, to.day, 23, 59, 59, 999);
      where.add('created_at <= ?');
      whereArgs.add(endOfDay.toIso8601String());
    }
    if (search != null && search.trim().isNotEmpty) {
      where.add('LOWER(customer_name) LIKE ?');
      whereArgs.add('%\${search.trim().toLowerCase()}%');
    }

    final orderRows = await database.query(
      'orders',
      where:     where.isEmpty ? null : where.join(' AND '),
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy:   'created_at DESC',
    );

    if (orderRows.isEmpty) return [];

    final orderIds     = orderRows.map((r) => r['id'] as String).toList();
    final placeholders = List.filled(orderIds.length, '?').join(',');

    final itemRows = await database.query(
      'order_items',
      where:     'order_id IN ($placeholders)',
      whereArgs: orderIds,
    );

    final itemsByOrder = <String, List<OrderItem>>{};
    for (final row in itemRows) {
      final item = OrderItem.fromMap(row);
      itemsByOrder.putIfAbsent(item.orderId, () => []).add(item);
    }

    return orderRows.map((row) {
      final id = row['id'] as String;
      return Order.fromMap(row, items: itemsByOrder[id] ?? []);
    }).toList();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Auto-save de rascunho
  // ─────────────────────────────────────────────────────────────────────────

  /// Salva um rascunho de pedido no SQLite IMEDIATAMENTE.
  ///
  /// Chamado a cada alteração no carrinho. Offline-first: sobrevive ao crash.
  ///
  /// @param orderId             UUID do pedido.
  /// @param customerId          ID do cliente.
  /// @param customerName        Nome do cliente.
  /// @param items               Lista de [CartItem] atual.
  /// @param notes               Observações (nullable).
  /// @param paymentSpeciesId    ID da espécie de pagamento (nullable).
  /// @param paymentSpeciesName  Descrição da espécie (nullable).
  /// @param paymentConditionId  ID da condição de pagamento (nullable).
  /// @param paymentConditionName  Descrição da condição (nullable).
  /// @param paymentDays         Prazo de pagamento (nullable).
  /// @param naturezaId          ID da natureza de operação (nullable).
  /// @param naturezaDescricao   Descrição da natureza (nullable).
  /// @param isDraft             Se true, salva como orçamento (sync_status='draft').
  Future<Order> saveDraft({
    required String orderId,
    required String companyId,
    required String customerId,
    required String customerName,
    required List<CartItem> items,
    String? notes,
    String? paymentSpeciesId,
    String? paymentSpeciesName,
    String? paymentConditionId,
    String? paymentConditionName,
    int?    paymentDays,
    int?    paymentInstallments,
    int?    paymentDaysPerInstallment,
    int?    paymentEntryDays,
    String? naturezaId,
    String? naturezaDescricao,
    bool    isDraft = false,
    double  orderDiscountInput = 0,
    String  orderDiscountMode  = 'percent',
  }) async {
    final database    = await _db.database;
    final now         = DateTime.now().toIso8601String();
    final totalAmount = items.fold<double>(0, (sum, i) => sum + i.totalPrice);
    final discValue   = items.fold<double>(0, (sum, i) => sum + i.discountValue);
    final gross       = items.fold<double>(0, (s, i) => s + i.product.price * i.quantity);
    final discPercent = gross > 0 ? discValue / gross * 100 : 0.0;

    final syncStatus = isDraft
        ? OrderSyncStatus.draft.name
        : OrderSyncStatus.pending.name;

    final orderMap = <String, dynamic>{
      'id':                  orderId,
      'company_id':          companyId,
      'customer_id':         customerId,
      'customer_name':       customerName,
      'total_amount':        totalAmount,
      'notes':               notes,
      'sync_status':         syncStatus,
      'created_at':          now,
      'updated_at':          now,
      'payment_species_id':  paymentSpeciesId,
      'payment_species_name': paymentSpeciesName,
      'payment_condition_id': paymentConditionId,
      'payment_condition_name': paymentConditionName,
      'payment_days':        paymentDays,
      'discount_percent':    discPercent,
      'discount_value':      discValue,
      'natureza_id':         naturezaId,
      'natureza_descricao':  naturezaDescricao,
      'order_discount_input': orderDiscountInput,
      'order_discount_mode':  orderDiscountMode,
    };

    // BLOCKER-2 fix: inclui colunas v21 apenas se o banco já foi migrado.
    // Evita 'table has no column' em dispositivos que ainda estão em v20
    // (possível em instalações que passaram por upgrade sem reiniciar o app).
    final dbVersion = await database.getVersion();
    if (dbVersion >= 21) {
      orderMap['payment_installments']         = paymentInstallments;
      orderMap['payment_days_per_installment'] = paymentDaysPerInstallment;
      orderMap['payment_entry_days']           = paymentEntryDays;
    }

    await database.transaction((txn) async {
      // IMPORTANTE: deletar os itens ANTES do upsert do cabeçalho.
      // Com PRAGMA foreign_keys=ON, ConflictAlgorithm.replace tenta
      // DELETE + INSERT na tabela orders. Se já existirem order_items
      // referenciando esse order_id, o DELETE falha por FK constraint
      // (sem CASCADE definido), abortando toda a transação silenciosamente.
      await txn.delete('order_items', where: 'order_id = ?', whereArgs: [orderId]);
      await txn.insert('orders', orderMap, conflictAlgorithm: ConflictAlgorithm.replace);
      for (final cartItem in items) {
        await txn.insert('order_items', {
          'id':                 _uuid.v4(),
          'order_id':           orderId,
          'product_code':       cartItem.product.code,
          'product_name':       cartItem.product.name,
          'quantity':           cartItem.quantity,
          'unit_price':         cartItem.product.price,
          'discount':           cartItem.discount,
          'total_price':        cartItem.totalPrice,
          'discount_mode':      cartItem.discountMode.name,
          'raw_discount_input': cartItem.rawDiscountInput,
        });
      }
    });

    return (await getById(orderId))!;
  }

  /// Converte um orçamento (draft) em pedido real, enfileirando para sync.
  ///
  /// @param orderId   UUID do orçamento a converter.
  /// @param sellerId  ID do vendedor (da sessão).
  /// @param companyId ID da empresa (da sessão).
  Future<Order> convertQuoteToOrder({
    required String orderId,
    required String sellerId,
    required String companyId,
  }) async {
    final order = await getById(orderId);
    if (order == null) throw StateError('Orçamento não encontrado: $orderId');
    if (!order.isDraft) throw StateError('Pedido $orderId não é um orçamento.');

    await _db.updateOrderSyncStatus(orderId, OrderSyncStatus.pending.name);

    final payload = order.copyWith(
      syncStatus: OrderSyncStatus.pending,
    ).toSyncPayload(sellerId, companyId);

    await _sync.enqueueOrder(orderId, payload);

    return order.copyWith(syncStatus: OrderSyncStatus.pending);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Confirmação de pedido
  // ─────────────────────────────────────────────────────────────────────────

  /// Confirma um rascunho, tornando-o imutável e enfileirando para sync.
  ///
  /// Offline-first: o pedido é persistido localmente ANTES de qualquer envio.
  ///
  /// @param orderId             UUID do pedido já salvo.
  /// @param sellerId            ID do vendedor (da sessão).
  /// @param companyId           ID da empresa (da sessão).
  /// @param paymentSpeciesId    ID da espécie de pagamento.
  /// @param paymentSpeciesName  Nome da espécie de pagamento.
  /// @param paymentConditionId  ID da condição de pagamento (nullable).
  /// @param paymentConditionName  Nome da condição de pagamento (nullable).
  /// @param paymentDays         Prazo (nullable).
  /// @param naturezaId          ID da natureza de operação (nullable).
  /// @param discountPercent     Desconto % calculado.
  /// @param discountValue       Desconto R$ calculado.
  Future<Order> confirmOrder({
    required String orderId,
    required String sellerId,
    required String companyId,
    required String paymentSpeciesId,
    required String paymentSpeciesName,
    String? paymentConditionId,
    String? paymentConditionName,
    int?    paymentDays,
    int?    paymentInstallments,
    int?    paymentDaysPerInstallment,
    int?    paymentEntryDays,
    String? naturezaId,
    double  discountPercent = 0,
    double  discountValue   = 0,
    required double grandTotal,
  }) async {
    final order = await getById(orderId);
    if (order == null) throw StateError('Pedido não encontrado: $orderId');

    await _db.updateOrderSyncStatus(orderId, OrderSyncStatus.pending.name);

    // Persiste desconto e total líquido correto (grandTotal vem do CartNotifier)
    final database = await _db.database;
    await database.update(
      'orders',
      {
        'discount_percent': discountPercent,
        'discount_value':   discountValue,
        'total_amount':     grandTotal,
      },
      where: 'id = ?',
      whereArgs: [orderId],
    );

    // Re-lê o pedido com total_amount atualizado
    final freshOrder = (await getById(orderId))!;

    final payload = freshOrder.copyWith(
      paymentSpeciesId:   paymentSpeciesId,
      paymentSpeciesName: paymentSpeciesName,
      paymentConditionId: paymentConditionId,
      paymentConditionName: paymentConditionName,
      paymentDays:        paymentDays,
      paymentInstallments:      paymentInstallments,
      paymentDaysPerInstallment: paymentDaysPerInstallment,
      paymentEntryDays:          paymentEntryDays,
      discountPercent:    discountPercent,
      discountValue:      discountValue,
      naturezaId:         naturezaId,
    ).toSyncPayload(sellerId, companyId);

    await _sync.enqueueOrder(orderId, payload);

    return freshOrder.copyWith(
      syncStatus:         OrderSyncStatus.pending,
      paymentSpeciesId:   paymentSpeciesId,
      paymentSpeciesName: paymentSpeciesName,
      paymentConditionId: paymentConditionId,
      paymentConditionName: paymentConditionName,
      paymentDays:        paymentDays,
      paymentInstallments:      paymentInstallments,
      paymentDaysPerInstallment: paymentDaysPerInstallment,
      paymentEntryDays:          paymentEntryDays,
      discountPercent:    discountPercent,
      discountValue:      discountValue,
      naturezaId:         naturezaId,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Cancelamento
  // ─────────────────────────────────────────────────────────────────────────

  /// Cancela e remove um pedido pendente localmente.
  ///
  /// @throws [StateError] se o pedido já foi sincronizado.
  Future<void> cancelOrder(String orderId) async {
    final order = await getById(orderId);
    if (order == null) return;

    if (order.isSynced) {
      throw StateError(
        'Pedido $orderId já foi confirmado no servidor. Não pode ser cancelado localmente.',
      );
    }

    final database = await _db.database;
    await database.transaction((txn) async {
      await txn.delete('order_items', where: 'order_id = ?', whereArgs: [orderId]);
      await txn.delete('orders', where: 'id = ?', whereArgs: [orderId]);
      await txn.delete('sync_queue', where: 'entity_id = ?', whereArgs: [orderId]);
    });
  }

  /// Gera um novo UUID para um novo pedido.
  String newOrderId() => _uuid.v4();
}

/// SyncService — Motor de sincronização offline-first.
///
/// Responsabilidades:
/// - Push: enviar pedidos pendentes ao middleware
/// - Pull: baixar delta de catálogo, clientes e vendedores do middleware
/// - Retry com backoff exponencial
/// - Prevenir reenvio de itens já sincronizados (idempotência local)
///
/// IMPORTANTE: node-firebird retorna chaves em MAIÚSCULAS.
///   Ex: { "CODE": "001", "NAME": "Produto X", "PRICE": 10.0 }
/// Todos os mapeamentos abaixo respeitam esse comportamento.
///
/// REGRA: Nunca bloqueia a UI. Toda operação é async.
/// REGRA: Falhas não são fatais — ficam na fila para retry.
library;

import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:get_it/get_it.dart';
import '../database/database_helper.dart';
import 'package:get_it/get_it.dart';
import '../session/session_service.dart';
import '../config/app_config_service.dart';
import '../network/connectivity_service.dart';
import '../services/notification_service.dart';
import '../services/company_settings_service.dart';
import 'package:get_it/get_it.dart' show GetIt;
import '../repositories/order_repository.dart';
import '../repositories/performance_repository.dart';
import '../session/session_service.dart';

/// Status possíveis de um item na fila de sincronização.
enum SyncStatus {
  pending,
  syncing,
  synced,
  error,
}

class SyncService {
  final DatabaseHelper _db;
  final ConnectivityService _connectivity;
  final Dio _dio;
  final NotificationService? _notifications;

  static const int _maxRetries       = 5;
  static const int _maxBackoffSeconds = 60;

  SyncService({
    required DatabaseHelper db,
    required ConnectivityService connectivity,
    required Dio dio,
    NotificationService? notifications,
  })  : _db = db,
        _connectivity = connectivity,
        _dio = dio,
        _notifications = notifications;

  // ─────────────────────────────────────────────────────────────────────────
  // PUSH — Mobile → Middleware → Firebird
  // ─────────────────────────────────────────────────────────────────────────

  // ─────────────────────────────────────────────────────────────────────────
  // Self Healing (Falsos Pendentes)
  // ─────────────────────────────────────────────────────────────────────────

  /// Repara pedidos retidos na UI no estado "Pendente" mas não enfileirados 
  /// no background (sync_queue). Acontecia ao reabrir rascunhos.
  Future<void> repairStuckPendingOrders() async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT o.id 
      FROM orders o
      WHERE o.sync_status = 'pending' 
        AND NOT EXISTS (
          SELECT 1 FROM sync_queue sq 
          WHERE sq.entity_id = o.id 
            AND sq.entity_type = 'order' 
            AND sq.sync_status IN ('pending', 'syncing')
        )
    ''');

    if (rows.isEmpty) return;
    debugPrint('[SyncService] repairStuckPendingOrders: Resgatando ${rows.length} pedidos presos.');

    try {
      final session = GetIt.I<SessionService>().activeSession;
      if (session == null) return;
      
      final repo = GetIt.I<OrderRepository>();

      for (final row in rows) {
        final orderId = row['id'] as String;
        try {
          final order = await repo.getById(orderId);
          if (order != null) {
             final payload = order.toSyncPayload(session.sellerId, session.companyId);
             await enqueueOrder(orderId, payload);
             debugPrint('[SyncService] Pedido $orderId recuperado e enfileirado para envio.');
          }
        } catch (e) {
          debugPrint('[SyncService] Erro ao recuperar pedido $orderId: $e');
        }
      }
    } catch (_) {}
  }

  /// Sincroniza todos os pedidos com status [SyncStatus.pending].
  ///
  /// Fluxo:
  /// 1. Repara pedidos presos (Auto-Healing)
  /// 2. Busca pedidos pending no SQLite
  /// 3. Envia em batch ao middleware (POST /api/sync/orders)
  /// 4. Atualiza sync_status de cada pedido conforme resposta
  /// 5. Em caso de erro, registra e agenda retry com backoff
  ///
  /// Retorna sumário: { pushed: n, duplicates: n, errors: n }
  Future<Map<String, int>> syncPendingOrders() async {
    final isOnline = await _connectivity.isOnline();
    if (!isOnline) return {'pushed': 0, 'skipped_offline': 1};

    await repairStuckPendingOrders();

    final queueItems = await _db.getSyncQueue(SyncStatus.pending.name);
    if (queueItems.isEmpty) return {'pushed': 0};

    final orderItems = queueItems
        .where((item) => item['entity_type'] == 'order')
        .toList();

    if (orderItems.isEmpty) return {'pushed': 0};

    final List<Map<String, dynamic>> ordersPayload = [];
    for (final item in orderItems) {
      try {
        ordersPayload.add(jsonDecode(item['payload'] as String));
        await _db.updateSyncStatus(item['id'] as String, SyncStatus.syncing.name);
        await _db.updateOrderSyncStatus(item['entity_id'] as String, SyncStatus.syncing.name);
      } catch (e) {
        await _db.updateSyncStatus(
          item['id'] as String,
          SyncStatus.error.name,
          errorMessage: 'Payload inválido: $e',
        );
      }
    }

    int pushed = 0, duplicates = 0, errors = 0;

    try {
      final response = await _dio.post('/api/sync/orders', data: {'orders': ordersPayload});
      final data     = response.data as Map<String, dynamic>;

      pushed     = data['accepted']   as int? ?? 0;
      duplicates = data['duplicates'] as int? ?? 0;

      // Constrói um Set com os IDs que o servidor reportou como ERRO
      final errorList  = (data['errors'] as List?) ?? [];
      errors           = errorList.length;
      final errorIds   = errorList
          .whereType<Map>()
          .map((e) => e['id']?.toString())
          .whereType<String>()
          .toSet();

      for (final item in orderItems) {
        final entityId = item['entity_id'] as String;
        final syncQueueId = item['id'] as String;

        if (errorIds.contains(entityId)) {
          // Pedido rejeitado pelo servidor (SP falhou no Firebird, etc.)
          final errorEntry = errorList
              .whereType<Map>()
              .firstWhere((e) => e['id'] == entityId, orElse: () => {});
          final errorMessage = errorEntry['reason']?.toString() ?? 'Erro no servidor';

          await _db.updateSyncStatus(
            syncQueueId,
            SyncStatus.error.name,
            errorMessage: errorMessage,
          );
          await _db.updateOrderSyncStatus(
            entityId,
            SyncStatus.error.name,
            errorMessage: errorMessage,
          );
        } else {
          // Pedido aceito ou duplicado — marca como sincronizado
          await _db.updateSyncStatus(syncQueueId, SyncStatus.synced.name);
          await _db.updateOrderSyncStatus(
            entityId,
            SyncStatus.synced.name,
            serverConfirmedAt: DateTime.now().toIso8601String(),
          );
        }
      }
    } on DioException catch (e) {
      for (final item in orderItems) {
        final retryCount = item['retry_count'] as int? ?? 0;

        if (retryCount >= _maxRetries) {
          await _db.updateSyncStatus(
            item['id'] as String,
            SyncStatus.error.name,
            errorMessage: 'Máximo de tentativas atingido: ${e.message}',
          );
          await _db.updateOrderSyncStatus(item['entity_id'] as String, SyncStatus.error.name);
        } else {
          await _db.updateSyncStatus(item['id'] as String, SyncStatus.pending.name);
          await _db.incrementRetryCount(item['id'] as String);
          await _db.updateOrderSyncStatus(item['entity_id'] as String, SyncStatus.pending.name);
        }
        errors++;
      }
    }

    return {'pushed': pushed, 'duplicates': duplicates, 'errors': errors};
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PULL — Catálogo de produtos
  // Endpoint: GET /api/sync/catalog
  // node-firebird retorna chaves UPPERCASE: CODE, NAME, PRICE, STOCK, etc.
  // Campos reais PIVETA.FDB (PRODUTOS JOIN PRODUTO_PRECOS):
  //   CODE, NAME, NAMESHORT, STOCK, UNIT, BRAND, BARCODE,
  //   REFERENCE, MAXDISCOUNT, UPDATEDAT, PRICE, PRICEMIN, PRICECOST
  // ─────────────────────────────────────────────────────────────────────────

  /// Baixa produtos alterados desde a última sincronização.
  ///
  /// Suporta paginação: faz loop de páginas (500 produtos/pg) até
  /// o middleware retornar `hasMore: false`.
  /// Backward-compatible com middleware sem paginação (sem campo `hasMore`).
  ///
  /// @returns Total de produtos inseridos/atualizados no SQLite.
  Future<int> pullCatalog() async {
    // Note: isOnline() check removed — connectivity_plus may return false on
    // Android even with working mobile data. Dio error handling covers real failures.

    int totalInserted = 0;
    int page          = 1;
    const int limit   = 1000;
    String? lastSyncedAt;
    bool deletedOld   = false;

    try {
      final currentSyncToken = DateTime.now().toIso8601String();

      while (true) {
        final response = await _dio.get(
          '/api/sync/catalog',
          queryParameters: {
            'page':  page,
            'limit': limit,
          },
        );

        final data     = response.data as Map<String, dynamic>;
        final products = (data['products'] as List?) ?? [];
        final hasMore  = data['hasMore'] as bool? ?? false;
        lastSyncedAt   = data['syncedAt'] as String?;

        if (products.isNotEmpty) {
          final now = currentSyncToken;
          final db  = await _db.database;

          // Filtra produtos sem code (PK NOT NULL) para não matar o batch inteiro
          final rows = <Map<String, dynamic>>[];
          for (final p in products) {
            final code = (p['CODE'] ?? p['code'])?.toString();
            if (code == null || code.isEmpty) continue;
            rows.add({
              'code':             code,
              'name':             _cleanOemChars(_trim(p['NAME']            ?? p['name'])),
              'name_short':       _trim(p['NAMESHORT']       ?? p['nameShort']       ?? p['nameshort']),
              'price':            _toDouble(p['PRICE']       ?? p['price'])          ?? 0.0,
              'price_min':        _toDouble(p['PRICEMIN']    ?? p['priceMin']        ?? p['pricemin']),
              'price_cost':       _toDouble(p['PRICECOST']   ?? p['priceCost']       ?? p['pricecost']),
              'stock':            _toDouble(p['STOCK']       ?? p['stock'])          ?? 0.0,
              'unit':             _trim(p['UNIT']            ?? p['unit']),
              'brand':            _trim(p['BRAND']           ?? p['brand']),
              'bar_code':         _trim(p['BARCODE']         ?? p['barCode']         ?? p['barcode']),
              'reference':        _trim(p['REFERENCE']       ?? p['reference']),
              'max_discount':     _toDouble(p['MAXDISCOUNT'] ?? p['maxDiscount']     ?? p['maxdiscount']),
              'category':         _trim(p['CATEGORY']        ?? p['category']),
              // FASE 4: Departamento ERP da filial padrão (exibição de estoque por filial)
              'erp_depto_padrao': _toInt(p['erpDeptoPadrao'] ?? p['ERPDEPTOPADRAO']),
              'last_synced_at':   now,
            });
          }

          // Insere em sub-lotes de 200 para evitar falha em batch gigante
          const chunkSize = 200;
          for (var i = 0; i < rows.length; i += chunkSize) {
            final end   = (i + chunkSize).clamp(0, rows.length);
            final chunk = rows.sublist(i, end);
            final batch = db.batch();
            for (final row in chunk) {
              batch.insert('products', row, conflictAlgorithm: ConflictAlgorithm.replace);
            }
            try {
              await batch.commit(noResult: true);
              totalInserted += chunk.length;
            } catch (e) {
              debugPrint('[SyncService] Catalog batch error (offset $i): $e');
            }
          }
        }

        // Sem mais páginas ou lista vazia
        if (!hasMore || products.isEmpty) break;
        page++;
      }

      // Após todas as páginas, remove produtos que não vieram nesta sincronização
      final db = await _db.database;
      final deleted = await db.delete('products', where: 'last_synced_at != ? OR last_synced_at IS NULL', whereArgs: [currentSyncToken]);
      debugPrint('[SyncService] pullCatalog → $deleted produtos obsoletos removidos.');

      final syncTime = lastSyncedAt ?? DateTime.now().toIso8601String();
      await _db.setSyncMetadata('last_catalog_sync', syncTime);
      return totalInserted;
    } on DioException {
      return totalInserted;
    }
  }


  // ─────────────────────────────────────────────────────────────────────────
  // PUSH — Clientes locais → Middleware → Firebird (MOB_CADASTRA_CLIENTE)
  // ─────────────────────────────────────────────────────────────────────────

  /// Envia ao ERP os clientes cadastrados localmente (IDs com prefixo "local_").
  ///
  /// Fluxo por cliente:
  ///   1. POST /api/sync/new-customer → middleware salva como pendente no PG
  ///   2. Worker processa no Firebird (MOB_CADASTRA_CLIENTE) e confirma
  ///   3. pullCustomers() traz o cliente com ID real do ERP
  ///
  /// Se receber erpId imediato (compatibilidade), atualiza direto.
  /// Se receber pendingId (novo fluxo), remove registro local e aguarda pull.
  ///
  /// @returns { pushed: n, errors: n }
  Future<Map<String, int>> pushLocalCustomers() async {
    final isOnline = await _connectivity.isOnline();
    if (!isOnline) return {'pushed': 0, 'skipped_offline': 1};

    final db = await _db.database;
    final localRows = await db.query(
      'customers',
      where: "id LIKE 'local_%'",
    );

    if (localRows.isEmpty) return {'pushed': 0};

    int pushed = 0;
    int errors = 0;

    for (final row in localRows) {
      final localId = row['id'] as String;
      try {
        final response = await _dio.post(
          '/api/sync/new-customer',
          data: {
            'localId':      localId,
            'name':         row['name'],
            'cnpj':         row['cnpj'],
            'email':        row['email'],
            'phone':        row['phone'],
            'zipCode':      row['zip_code'],
            'city':         row['city'],
            'state':        row['state'],
            'street':       row['street'],
            'streetNumber': row['street_number'],
            'neighborhood': row['neighborhood'],
            'sellerId':     row['seller_id'],
          },
        );

        if (response.statusCode == 201) {
          final data = response.data as Map<String, dynamic>;
          final erpId = data['erpId']?.toString();

          if (erpId != null && erpId.isNotEmpty) {
            // Fluxo síncrono (legado): erpId veio direto
            await db.update('orders', {'customer_id': erpId},
                where: 'customer_id = ?', whereArgs: [localId]);
          }

          // Remove registro local — pullCustomers() recupera com ID ERP real
          // (tanto no fluxo síncrono quanto assíncrono via Worker)
          await db.delete('customers', where: 'id = ?', whereArgs: [localId]);
          pushed++;
        }
      } on DioException {
        errors++;
      }
    }

    return {'pushed': pushed, 'errors': errors};
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PULL — Clientes
  // Endpoint: GET /api/sync/customers
  // Campos reais PIVETA.FDB (MOB_LISTACLIENTES):
  //   ID, NAME, TRADENAME, CNPJ, ADDRESS, CITY, STATE,
  //   PHONE, MOBILE, EMAIL, SELLERID, SELLERCODE, CREDITLIMIT, STATUS
  // ─────────────────────────────────────────────────────────────────────────

  /// Baixa clientes alterados desde a última sincronização.
  ///
  /// @returns Número de clientes inseridos/atualizados.
  Future<int> pullCustomers() async {
    // Note: isOnline() check removed — connectivity_plus may return false on
    // Android even with working mobile data. Dio error handling covers real failures.

    int totalInserted = 0;
    int page          = 1;
    const int limit   = 1000;
    String? lastSyncedAt;

    try {
      while (true) {
        final response = await _dio.get(
          '/api/sync/customers',
          queryParameters: {
            'page':  page,
            'limit': limit,
          },
        );

        final data     = response.data as Map<String, dynamic>;
        final rawList  = (data['customers'] as List?) ?? [];
        final hasMore  = data['hasMore'] as bool? ?? false;
        lastSyncedAt   = data['syncedAt'] as String?;

        if (rawList.isNotEmpty) {
          final now = DateTime.now().toIso8601String();
          final db  = await _db.database;

          // Filtra registros com id nulo (violaria PRIMARY KEY NOT NULL)
          final rows = <Map<String, dynamic>>[];
          for (final c in rawList) {
            final id = (c['ID'] ?? c['id'])?.toString();
            if (id == null || id.isEmpty) continue;
            rows.add({
              'id':             id,
              'name':           _cleanOemChars(_trim(c['NAME']              ?? c['name']))                   ?? '',
              'cnpj':           _trim(c['CNPJ']              ?? c['cnpj']),
              'phone':          _trim(c['PHONE']             ?? c['phone'] ?? c['MOBILE']   ?? c['mobile']),
              'email':          _trim(c['EMAIL']             ?? c['email']),
              'street':         _trim(c['STREET']            ?? c['street']                 ?? c['ENDERECO']    ?? c['endereco']),
              'street_number':  _trim(c['STREETNUMBER']      ?? c['streetNumber']            ?? c['streetnumber']),
              'neighborhood':   _trim(c['NEIGHBORHOOD']      ?? c['neighborhood']            ?? c['BAIRRO']     ?? c['bairro']),
              'zip_code':       _trim(c['ZIPCODE']           ?? c['zipCode']                 ?? c['zipcode']     ?? c['CEP']      ?? c['cep']),
              'city':           _trim(c['CITY']              ?? c['city']),
              'state':          _trim(c['STATE']             ?? c['state']),
              'credit_limit':   _toDouble(c['CREDITLIMIT']   ?? c['creditLimit']             ?? c['creditlimit']) ?? 0.0,
              'seller_id':      (c['SELLERID'] ?? c['sellerId'] ?? c['sellerid'])?.toString(),
              // Tabela de preço vinculada ao cliente (CLIENTES.ID_TABELA via Worker)
              'price_table_id': (c['PRICETABLEID'] ?? c['priceTableId'] ?? c['pricetableid'])?.toString(),
              'last_synced_at': now,
            });
          }

          if (rows.isNotEmpty) {
            // Sub-lotes de 200 para segurança
            const chunkSize = 200;
            for (var i = 0; i < rows.length; i += chunkSize) {
              final end   = (i + chunkSize).clamp(0, rows.length);
              final chunk = rows.sublist(i, end);
              final batch = db.batch();
              for (final row in chunk) {
                batch.insert('customers', row, conflictAlgorithm: ConflictAlgorithm.replace);
              }
              try {
                await batch.commit(noResult: true);
                totalInserted += chunk.length;
              } catch (e) {
                debugPrint('[SyncService] Customer batch error (page $page, offset $i): $e');
              }
            }
            debugPrint('[SyncService] pullCustomers page $page: ${rows.length} clientes (total: $totalInserted)');
          }
        }

        if (!hasMore || rawList.isEmpty) break;
        page++;
      }

      final syncTime = lastSyncedAt ?? DateTime.now().toIso8601String();
      await _db.setSyncMetadata('last_customers_sync', syncTime);
      return totalInserted;
    } on DioException catch (e) {
      debugPrint('[SyncService] HTTP Error pulling customers (page $page): ${e.message}');
      return totalInserted;
    } catch (e) {
      debugPrint('[SyncService] Generic Error pulling customers (page $page): $e');
      return totalInserted;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PULL — Vendedores (sellers)
  // Endpoint: GET /api/sync/sellers
  // Campos reais PIVETA.FDB (FUNCIONARIOS WHERE MOB_ACESSO=1):
  //   ID, MOBILEID, NAME, EMAIL, PASSWORDHASH (= MOB_SENHA),
  //   MAXDISCOUNT, COMMISSIONRATE
  //
  // O campo PASSWORDHASH contém o PIN em texto claro gravado pelo ERP.
  // É salvo localmente apenas para validação offline. Não é exibido na UI.
  // ─────────────────────────────────────────────────────────────────────────

  /// Baixa vendedores com acesso mobile e salva localmente.
  ///
  /// O PIN (MOB_SENHA) é armazenado no SQLite para autenticação offline.
  /// Chamado na primeira sincronização e a cada 24h.
  ///
  /// @returns Número de vendedores inseridos/atualizados.
  Future<int> pullSellers() async {
    // Note: isOnline() check removed — connectivity_plus may return false on
    // Android even with working mobile data. Dio error handling covers real failures.
    try {
      final response = await _dio.get('/api/sync/sellers');

      final data     = response.data as Map<String, dynamic>;
      final rawList  = (data['sellers'] as List?) ?? [];
      final syncedAt = (data['syncedAt'] as String?) ?? DateTime.now().toIso8601String();

      debugPrint('[SyncService] pullSellers → source=${data['source']} count=${rawList.length}');

      if (rawList.isNotEmpty) {
        final now   = DateTime.now().toIso8601String();
        final db    = await _db.database;
        final batch = db.batch();

        for (final s in rawList) {
          batch.insert('sellers', {
            'id':            s['ID']?.toString()           ?? s['id']?.toString(),
            'mobile_id':     s['MOBILEID']?.toString()     ?? s['mobileId']?.toString()     ?? s['mobileid']?.toString(),
            'name':          _trim(s['NAME']               ?? s['name'])        ?? '',
            'email':         _trim(s['EMAIL']              ?? s['email']),
            'pin':           s['PASSWORDHASH']?.toString() ?? s['passwordHash']?.toString() ?? s['passwordhash']?.toString(),
            'max_discount':  _toDouble(s['MAXDISCOUNT']    ?? s['maxDiscount']              ?? s['maxdiscount']),
            'commission':    _toDouble(s['COMMISSIONRATE'] ?? s['commissionRate']           ?? s['commissionrate']),
            'erp_empresa_id': _toInt(s['ERPEMPRESAID'] ?? s['erpEmpresaId'] ?? s['erpempresaid']),
            'last_synced_at': now,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }

        await batch.commit(noResult: true);
        debugPrint('[SyncService] pullSellers → ${rawList.length} vendedores inseridos no SQLite');
      }

      await _db.setSyncMetadata('last_sellers_sync', syncedAt);
      return rawList.length;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final msg    = e.response?.data?.toString() ?? e.message ?? 'Erro de rede';
      debugPrint('[SyncService] pullSellers DioException: status=$status msg=$msg');

      // Erros de autenticação/servidor merecem mensagem visível ao usuário
      if (status != null && status >= 400) {
        throw Exception('Erro ao sincronizar vendedores (HTTP $status): verifique a API Key e URL do servidor.');
      }

      // Erros de rede (timeout, sem conexão) — propaga para LoginScreen exibir
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.unknown) {
        final uri = e.requestOptions.uri;
        throw Exception(
          'Não foi possível conectar ao servidor ($uri). '
          'Verifique a URL e a conexão com internet.',
        );
      }

      // Outros erros de rede (receiveTimeout, cancel) → falha silenciosa
      return 0;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PULL — Espécies de Pagamento
  // Endpoint: GET /api/sync/payment-species
  // ─────────────────────────────────────────────────────────────────────────

  /// Baixa espécies de pagamento disponíveis para o app móvel.
  ///
  /// Resultado armazenado em `payment_species` no SQLite local.
  /// Chamado a cada sincronização de catálogo (dados raramente mudam).
  ///
  /// @returns Número de espécies inseridas/atualizadas.
  Future<int> pullPaymentSpecies() async {
    final isOnline = await _connectivity.isOnline();
    if (!isOnline) return 0;

    try {
      final response = await _dio.get('/api/sync/payment-species');

      final data     = response.data as Map<String, dynamic>;
      // Middleware retorna { data: [...], syncedAt: ... } na v2 ou { paymentMethods: ... } na v1
      final rawList  = (data['paymentMethods'] as List?) ??
                       (data['data'] as List?) ??  // fallback para versões antigas
                       [];
      final syncedAt = data['syncedAt'] as String? ?? DateTime.now().toIso8601String();

      if (rawList.isNotEmpty) {
        final now   = DateTime.now().toIso8601String();
        final db    = await _db.database;
        final batch = db.batch();

        for (final s in rawList) {
          final id = _trim(s['ID'] ?? s['id'] ?? s['Id'] ?? s['payment_species_id'] ?? s['paymentSpeciesId']);
          if (id == null) continue;

          batch.insert('payment_species', {
            'payment_species_id': id,
            'name':               _trim(s['NAME'] ?? s['name'] ?? s['Name']) ?? '',
            'type':               (s['TYPE'] ?? s['type'] ?? s['Type'])?.toString(),
            'days':               _toInt(s['DAYS'] ?? s['days'] ?? s['Days']),
            'last_synced_at':     now,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }

        await batch.commit(noResult: true);
      }

      await _db.setSyncMetadata('last_payment_species_sync', syncedAt);
      return rawList.length;
    } catch (e) {
      debugPrint('[SyncService] pullPaymentSpecies error: $e');
      return 0;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PULL — Condições de Pagamento
  // Endpoint: GET /api/sync/payment-conditions
  // ─────────────────────────────────────────────────────────────────────────

  /// Baixa condições de pagamento disponíveis para o app móvel.
  ///
  /// @returns Número de condições inseridas/atualizadas.
  Future<int> pullPaymentConditions() async {
    final isOnline = await _connectivity.isOnline();
    if (!isOnline) return 0;

    try {
      final response = await _dio.get('/api/sync/payment-conditions');

      final data     = response.data as Map<String, dynamic>;
      final rawList  = (data['data'] as List?) ?? [];
      final syncedAt = data['syncedAt'] as String? ?? DateTime.now().toIso8601String();

      if (rawList.isNotEmpty) {
        // timestamp not needed in payment_conditions batch (no last_synced_at column)
        final db    = await _db.database;
        final batch = db.batch();

        for (final c in rawList) {
          final id = _trim(c['ID'] ?? c['id'] ?? c['Id']);
          if (id == null) continue;

          batch.insert('payment_conditions', {
            'id':            id,
            'descricao':     _trim(c['DESCRICAO']         ?? c['descricao']               ?? c['Descricao']) ?? '',
            'especie_id':    c['ESPECIEID']?.toString()   ?? c['especieId']?.toString()   ?? c['especieid']?.toString() ?? c['EspecieId']?.toString() ?? c['especie_id']?.toString(),
            'desconto_max':  _toDouble(c['DESCONTOMAX']   ?? c['descontoMax']             ?? c['descontomax']           ?? c['DescontoMax']           ?? c['desconto_max']),
            'parcelas':      _toInt(c['PARCELAS']         ?? c['parcelas']                ?? c['Parcelas']),
            'dias_entrada':  _toInt(c['DIASENTRADA']      ?? c['diasEntrada']             ?? c['diasentrada']           ?? c['DiasEntrada']           ?? c['dias_entrada']),
            'dias_parcelas': _toInt(c['DIASPARCELAS']     ?? c['diasParcelas']            ?? c['diasparcelas']          ?? c['DiasParcelas']          ?? c['dias_parcelas']),
            'mob_ordem':     _toInt(c['MOBORDEM']         ?? c['mobOrdem']                ?? c['mobordem']              ?? c['MobOrdem']              ?? c['mob_ordem']),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }

        await batch.commit(noResult: true);
      }

      await _db.setSyncMetadata('last_payment_conditions_sync', syncedAt);
      return rawList.length;
    } catch (e) {
      debugPrint('[SyncService] pullPaymentConditions error: $e');
      return 0;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PULL — Naturezas de Operação
  // Endpoint: GET /api/sync/natureza
  // Campos: id, descricao, descricaoNota, codigoFiscal, es, mobOrdem
  // (filtro MOB_ACESSO='S' + ORDER BY MOB_ORDEM aplicado no Worker)
  // ─────────────────────────────────────────────────────────────────────────

  /// Baixa naturezas de operação disponíveis para o app móvel.
  ///
  /// Resultado armazenado em `natureza_operacao` no SQLite local.
  /// Chamado a cada sincronização de catálogo.
  ///
  /// @returns Número de naturezas inseridas/atualizadas.
  Future<int> pullNatureza() async {
    final isOnline = await _connectivity.isOnline();
    if (!isOnline) return 0;

    try {
      final response = await _dio.get('/api/sync/natureza');

      final data     = response.data as Map<String, dynamic>;
      // Middleware retorna { natureza: [...], syncedAt: ..., source: ... }
      final rawList  = (data['natureza'] as List?) ??
                       (data['data'] as List?) ??  // fallback para versões antigas
                       [];
      final syncedAt = data['syncedAt'] as String? ?? DateTime.now().toIso8601String();

      if (rawList.isNotEmpty) {
        final now   = DateTime.now().toIso8601String();
        final db    = await _db.database;
        final batch = db.batch();

        for (final n in rawList) {
          final id = _trim(n['ID'] ?? n['id'] ?? n['Id'] ?? n['natureza_id'] ?? n['naturezaId']);
          if (id == null) continue;

          batch.insert('natureza_operacao', {
            'natureza_id':    id,
            'descricao':      _trim(n['DESCRICAO']      ?? n['descricao']             ?? n['Descricao']) ?? '',
            'descricao_nota': _trim(n['DESCRICAONOTA']   ?? n['descricaoNota']        ?? n['descricaonota']   ?? n['DescricaoNota'] ?? n['descricao_nota']),
            'codigo_fiscal':  _trim(n['CODIGOFISCAL']   ?? n['codigoFiscal']          ?? n['codigofiscal']    ?? n['CodigoFiscal']  ?? n['codigo_fiscal']),
            'es':             _trim(n['ES']             ?? n['es']                    ?? n['Es']),
            'mob_ordem':      _toInt(n['MOBORDEM']      ?? n['mobOrdem']              ?? n['mobordem']        ?? n['MobOrdem']      ?? n['mob_ordem']),
            'last_synced_at': now,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }

        await batch.commit(noResult: true);
      }

      await _db.setSyncMetadata('last_natureza_sync', syncedAt);
      return rawList.length;
    } catch (e) {
      debugPrint('[SyncService] pullNatureza error: $e');
      return 0;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PULL — Tabelas de Preço
  // Endpoints: GET /api/sync/price-tables  +  GET /api/sync/product-prices
  // Gerado pelo Worker via TABELA_PRECOS + MOB_TABELAPRECO.
  // ─────────────────────────────────────────────────────────────────────────

  /// Baixa tabelas de preço (cabeçalhos + preços produto×tabela) do middleware.
  ///
  /// Dois endpoints consultados:
  ///   1. /api/sync/price-tables   → tabela price_tables
  ///   2. /api/sync/product-prices → tabela product_prices
  ///
  /// @returns Total combinado de registros salvos.
  Future<int> pullPriceTables() async {
    int total = 0;

    try {
      // 1. Cabeçalhos das tabelas
      final tablesResp = await _dio.get('/api/sync/price-tables');
      final tablesData = tablesResp.data as Map<String, dynamic>;
      final tablesList = (tablesData['tables'] as List?) ?? [];

      if (tablesList.isNotEmpty) {
        final db    = await _db.database;
        final batch = db.batch();
        // Limpa antes de re-popular (tabelas podem ser alteradas no ERP)
        batch.delete('price_tables');
        for (final t in tablesList) {
          batch.insert('price_tables', {
            'id':         (t['id'] ?? t['ID'] ?? '').toString(),
            'name':       _trim(t['name'] ?? t['NAME'] ?? t['Name']) ?? '',
            'markup_pct': _toDouble(t['markupPct'] ?? t['markuppct'] ?? t['MARKUPPCT'] ?? 0) ?? 0.0,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        await batch.commit(noResult: true);
        total += tablesList.length;
        debugPrint('[SyncService] pullPriceTables → ${tablesList.length} tabelas salvas');
      }

      // 2. Preços produto × tabela
      final pricesResp = await _dio.get('/api/sync/product-prices');
      final pricesData = pricesResp.data as Map<String, dynamic>;
      final pricesList = (pricesData['prices'] as List?) ?? [];

      if (pricesList.isNotEmpty) {
        final db = await _db.database;
        final currentSyncToken = DateTime.now().toIso8601String();
        
        // Insere em lotes de 500 com a marcação do sync atual
        const chunkSize = 500;
        for (var i = 0; i < pricesList.length; i += chunkSize) {
          final end   = (i + chunkSize).clamp(0, pricesList.length);
          final chunk = pricesList.sublist(i, end);
          final batch = db.batch();
          for (final p in chunk) {
            final code    = (p['productCode'] ?? p['productcode'] ?? p['PRODUCTCODE'] ?? '').toString();
            final tableId = (p['priceTableId'] ?? p['pricetableid'] ?? p['PRICETABLEID'] ?? '').toString();
            final price   = _toDouble(p['price'] ?? p['PRICE'] ?? 0) ?? 0.0;
            if (code.isNotEmpty && tableId.isNotEmpty) {
              batch.insert('product_prices', {
                'product_code':   code,
                'price_table_id': tableId,
                'price':          price,
                'last_synced_at': currentSyncToken,
              }, conflictAlgorithm: ConflictAlgorithm.replace);
            }
          }
          await batch.commit(noResult: true);
        }

        // Remove os preços antigos que não vieram nesta sincronização
        await db.delete('product_prices', where: 'last_synced_at != ? OR last_synced_at IS NULL', whereArgs: [currentSyncToken]);

        total += pricesList.length;
        debugPrint('[SyncService] pullPriceTables → ${pricesList.length} preços salvos');
      }
    } catch (e) {
      debugPrint('[SyncService] pullPriceTables error: $e');
    }

    return total;
  }

  /// Sincroniza as configurações comportamentais da empresa.
  ///
  /// Consulta `GET /api/sync/company-settings` e persiste o resultado no
  /// SQLite via [CompanySettingsService.save]. Atualiza o singleton em memória
  /// para que CartNotifier e UI sejam afetados imediatamente.
  ///
  /// Campos sincronizados:
  ///   - `priceTableMode` ("none" | "product" | "prompt")
  ///   - `allowNegativeStock` (true | false) — venda sem estoque
  ///
  /// @returns 1 se sincronizado com sucesso, 0 caso contrário.
  Future<int> pullCompanySettings() async {
    try {
      final resp = await _dio.get('/api/sync/company-settings');
      final data = resp.data as Map<String, dynamic>;
      final mode               = (data['priceTableMode'] as String?)?.trim() ?? 'none';
      final allowNegativeStock = data['allowNegativeStock'] as bool? ?? false;

      // Persiste localmente e atualiza o singleton em memória
      try {
        final GetIt locator = GetIt.instance;
        if (locator.isRegistered<CompanySettingsService>()) {
          await locator<CompanySettingsService>().save(
            mode,
            allowNegativeStock: allowNegativeStock,
          );
        }
      } catch (_) {}

      debugPrint('[SyncService] pullCompanySettings → priceTableMode: $mode | allowNegativeStock: $allowNegativeStock');
      return 1;
    } catch (e) {
      debugPrint('[SyncService] pullCompanySettings error: $e');
      return 0;
    }
  }

  /// Busca o PIN armazenado localmente para o vendedor com [sellerId].
  ///
  /// Retorna null se o vendedor não foi sincronizado ainda.
  Future<String?> getSellerPin(String sellerId) async {
    final db   = await _db.database;
    final rows = await db.query(
      'sellers',
      columns: ['pin'],
      where: 'id = ?',
      whereArgs: [sellerId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['pin'] as String?;
  }

  /// Busca dados do vendedor localmente por ID do funcionário.
  Future<Map<String, dynamic>?> getSellerById(String sellerId) async {
    final db   = await _db.database;
    final rows = await db.query(
      'sellers',
      where: 'id = ?',
      whereArgs: [sellerId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PULL de status dos pedidos enviados
  // Endpoint: GET /api/orders/{id}
  // Busca erp_order_id para pedidos confirmados sem número ERP ainda
  // ─────────────────────────────────────────────────────────────────────────

  /// Atualiza status e erpOrderId de pedidos enviados à VPS.
  ///
  /// Consulta somente pedidos com `sync_status = 'synced'` e `erp_order_id` NULL,
  /// para obter o número ERP Firebird retornado pelo Worker após confirmar.
  ///
  /// @returns Número de pedidos atualizados com erpOrderId.
  Future<int> pullOrderStatuses() async {
    final isOnline = await _connectivity.isOnline();
    if (!isOnline) return 0;

    final db = await _db.database;
    // Pedidos confirmados mas sem número ERP ainda
    final rows = await db.query(
      'orders',
      where:     "sync_status = 'synced' AND erp_order_id IS NULL",
      columns:   ['id'],
      limit:     20,
    );

    if (rows.isEmpty) return 0;

    int updated = 0;

    for (final row in rows) {
      final orderId = row['id'] as String;
      try {
        final response = await _dio.get('/api/orders/$orderId');
        final data = response.data as Map<String, dynamic>?;

        final erpId        = data?['erpOrderId']?.toString();
        final serverStatus = data?['status'] as String? ?? data?['syncStatus'] as String? ?? data?['sync_status'] as String?;
        final errMsg       = data?['errorMessage']?.toString() ?? data?['error_message']?.toString();

        if (erpId != null || serverStatus != null) {
          final prevRows = await db.query('orders',
              columns: ['customer_name'], where: 'id = ?', whereArgs: [orderId]);
          final customerName = prevRows.isNotEmpty
              ? (prevRows.first['customer_name'] as String?) ?? ''
              : '';

          await _db.updateOrderSyncStatus(
            orderId,
            serverStatus ?? 'synced',
            erpOrderId: erpId,
            errorMessage: errMsg,
          );
          updated++;

          // Feature D — notificação local
          final notifs = _notifications;
          if (notifs != null) {
            if (erpId != null) {
              await notifs.notifyOrderSynced(
                orderId:      orderId,
                customerName: customerName,
                erpOrderId:   erpId,
              );
            } else if (serverStatus == 'error') {
              final finalErrMsg = errMsg ?? 'Erro desconhecido';
              await notifs.notifyOrderError(
                orderId:      orderId,
                customerName: customerName,
                errorMessage: finalErrMsg,
              );
            }
          }
        }
      } on DioException {
        // Falha silenciosa — tentará novamente no próximo ciclo
      }
    }

    return updated;
  }

  /// Baixa o histórico de pedidos do vendedor da VPS e os restaura no SQLite.
  /// Chamado na sincronização automática em background ou manual.
  Future<int> pullHistoricalOrders(String sellerId) async {
    final isOnline = await _connectivity.isOnline();
    if (!isOnline) {
      debugPrint('[SyncService] pullHistoricalOrders: offline, ignorando.');
      return 0;
    }

    try {
      debugPrint('[SyncService] pullHistoricalOrders para sellerId=$sellerId');
      final response = await _dio.get(
        '/api/orders',
        queryParameters: {'sellerId': sellerId},
      );

      final data = response.data as Map<String, dynamic>?;
      if (data == null) return 0;

      final rawOrders = data['orders'] as List<dynamic>? ?? [];
      if (rawOrders.isEmpty) {
        debugPrint('[SyncService] pullHistoricalOrders: nenhum pedido retornado.');
        return 0;
      }

      final db = await _db.database;
      int importedCount = 0;

      await db.transaction((txn) async {
        for (final item in rawOrders) {
          final row = item as Map<String, dynamic>;
          final payload = row['payload'] as Map<String, dynamic>?;
          
          if (payload == null) {
            continue;
          }

          final orderId = (row['id'] ?? payload['id'])?.toString();
          if (orderId == null || orderId.isEmpty) continue;

          final companyId = _trim(row['company_id'] ?? payload['companyId']) ?? '1';
          final customerId = _trim(payload['customerId']) ?? '';
          String customerName = _trim(row['customerName'] ?? payload['customerName'] ?? row['customer_name'] ?? '') ?? '';

          final isNumeric = double.tryParse(customerName) != null;
          if (customerName.isEmpty || isNumeric || customerName == customerId) {
            final custRows = await txn.query(
              'customers',
              columns: ['name'],
              where: 'id = ?',
              whereArgs: [customerId],
              limit: 1,
            );
            if (custRows.isNotEmpty) {
              customerName = _trim(custRows.first['name']?.toString()) ?? customerName;
            }
          }

          final totalAmount = _toDouble(row['totalAmount'] ?? payload['totalAmount'] ?? row['total_amount']) ?? 0.0;
          final notes = _trim(payload['notes']);
          final syncStatus = _trim(row['syncStatus'] ?? row['sync_status']) ?? 'synced';
          final createdAt = _trim(row['createdAt'] ?? payload['createdAt'] ?? row['created_at']) ?? DateTime.now().toIso8601String();
          final updatedAt = _trim(row['updatedAt'] ?? payload['updatedAt'] ?? row['updated_at']) ?? DateTime.now().toIso8601String();
          final serverConfirmedAt = _trim(row['server_confirmed_at'] ?? row['updatedAt'] ?? row['updated_at']);
          final erpOrderId = _trim(row['erpOrderId'] ?? row['erp_order_id'] ?? payload['erpOrderId']);
          final errorMessage = _trim(row['errorMessage'] ?? row['error_message']);

          final paymentSpeciesId = _trim(payload['paymentSpeciesId']);
          final paymentSpeciesName = _trim(payload['paymentSpeciesName']);
          final paymentConditionId = _trim(payload['paymentConditionId']);
          final paymentConditionName = _trim(payload['paymentConditionName']);
          final paymentDays = _toInt(payload['paymentDays']) ?? 0;
          final paymentInstallments = _toInt(payload['paymentInstallments']) ?? 1;
          final paymentDaysPerInstallment = _toInt(payload['paymentDaysPerInstallment']) ?? 30;
          final paymentEntryDays = _toInt(payload['paymentEntryDays']) ?? 0;

          final discountPercent = _toDouble(payload['discountPercent']) ?? 0.0;
          final discountValue = _toDouble(payload['discountValue']) ?? 0.0;

          final naturezaId = _trim(payload['naturezaId']);
          final naturezaDescricao = _trim(payload['naturezaDescricao']);

          // Inferência dos campos de desconto para restaurar a tela do Carrinho (UI)
          double orderDiscountInput = 0.0;
          String orderDiscountMode = 'percent';
          if (discountPercent > 0) {
            orderDiscountInput = discountPercent;
            orderDiscountMode = 'percent';
          } else if (discountValue > 0) {
            orderDiscountInput = discountValue;
            orderDiscountMode = 'value';
          }

          // Salva/Substitui cabeçalho
          await txn.insert(
            'orders',
            {
              'id': orderId,
              'company_id': companyId,
              'customer_id': customerId,
              'customer_name': customerName,
              'total_amount': totalAmount,
              'notes': notes,
              'sync_status': syncStatus,
              'created_at': createdAt,
              'updated_at': updatedAt,
              'server_confirmed_at': serverConfirmedAt,
              'payment_species_id': paymentSpeciesId,
              'payment_species_name': paymentSpeciesName,
              'payment_condition_id': paymentConditionId,
              'payment_condition_name': paymentConditionName,
              'payment_days': paymentDays,
              'payment_installments': paymentInstallments,
              'payment_days_per_installment': paymentDaysPerInstallment,
              'payment_entry_days': paymentEntryDays,
              'discount_percent': discountPercent,
              'discount_value': discountValue,
              'natureza_id': naturezaId,
              'natureza_descricao': naturezaDescricao,
              'error_message': errorMessage,
              'erp_order_id': erpOrderId,
              'order_discount_input': orderDiscountInput,
              'order_discount_mode': orderDiscountMode,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );

          // Limpa itens antigos deste pedido antes de reinserir (evitar FKey ou duplicatas)
          await txn.delete(
            'order_items',
            where: 'order_id = ?',
            whereArgs: [orderId],
          );

          // Salva itens
          final rawItems = payload['items'] as List<dynamic>? ?? [];
          for (final rawItem in rawItems) {
            final itemMap = rawItem as Map<String, dynamic>;
            final itemId = _trim(itemMap['id']) ?? const Uuid().v4();
            final productCode = _trim(itemMap['productCode'] ?? itemMap['product_code']) ?? '';
            final productName = _trim(itemMap['productName'] ?? itemMap['product_name']) ?? '';
            final quantity = _toDouble(itemMap['quantity']) ?? 0.0;
            final unitPrice = _toDouble(itemMap['unitPrice'] ?? itemMap['unit_price']) ?? 0.0;
            final discount = _toDouble(itemMap['discount']) ?? 0.0; // percentual efetivo
            final totalPrice = _toDouble(itemMap['totalPrice'] ?? itemMap['total_price']) ?? 0.0;
            final discountMode = _trim(itemMap['discountMode'] ?? itemMap['discount_mode']) ?? 'percent';
            
            // O app calcula rawDiscountInput. Se for nulo no payload (legado), deduzimos do discount
            final rawDiscountInput = _toDouble(itemMap['rawDiscountInput'] ?? itemMap['raw_discount_input'] ?? itemMap['discount']) ?? 0.0;

            await txn.insert(
              'order_items',
              {
                'id': itemId,
                'order_id': orderId,
                'product_code': productCode,
                'product_name': productName,
                'quantity': quantity,
                'unit_price': unitPrice,
                'discount': discount,
                'total_price': totalPrice,
                'discount_mode': discountMode,
                'raw_discount_input': rawDiscountInput,
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
          importedCount++;
        }
      });

      debugPrint('[SyncService] pullHistoricalOrders: $importedCount pedidos importados com sucesso.');
      return importedCount;
    } catch (e) {
      debugPrint('[SyncService] Erro ao sincronizar histórico de pedidos: $e');
      return 0;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PULL — Títulos financeiros do cliente
  // Endpoint: GET /api/sync/financials?customerId={id}
  // ─────────────────────────────────────────────────────────────────────────

  /// Baixa todos os títulos financeiros do middleware e salva localmente.
  ///
  /// Chamado no ciclo automático do AutoSyncService para manter
  /// o SQLite atualizado com os dados do Worker (MOB_LISTACONTAS).
  ///
  /// @returns Número de títulos inseridos/atualizados.
  Future<int> pullFinancials() async {
    final isOnline = await _connectivity.isOnline();
    if (!isOnline) return 0;

    try {
      final response = await _dio.get('/api/sync/financials');

      final data  = response.data as Map<String, dynamic>?;
      final items = data?['financials'] as List? ?? [];

      if (items.isEmpty) return 0;

      final db    = await _db.database;
      final batch = db.batch();
      final now   = DateTime.now().toIso8601String();

      for (final raw in items) {
        final f = raw as Map<String, dynamic>;
        batch.insert('financials', {
          'id':                  _trim(f['id'])?.toString() ?? '',
          'customer_id':         _trim(f['customerId'])?.toString() ?? '',
          'doc_number':          _trim(f['docNumber']),
          'amount':              _toDouble(f['amount']) ?? 0.0,
          'interest':            _toDouble(f['interest']) ?? 0.0,
          'due_date':            _trim(f['dueDate']),
          'payment_species_id':  _trim(f['paymentSpeciesId']),
          'is_paid':             (f['isPaid'] as bool? ?? false) ? 1 : 0,
          'type':                _trim(f['type']),
          'payment_date':        _trim(f['paymentDate']),
          'last_synced_at':      now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      await batch.commit(noResult: true);
      debugPrint('[SyncService] pullFinancials: ${items.length} títulos salvos');
      return items.length;
    } on DioException {
      return 0;
    }
  }




  ///
  /// Chamado quando o vendedor seleciona um cliente na CatalogScreen,
  /// para exibir saldo devedor em tempo real antes de confirmar o pedido.
  ///
  /// @param customerId  ID do cliente Firebird.
  /// @returns           Número de títulos inseridos/atualizados.
  Future<int> pullFinancialsForCustomer(String customerId) async {
    final isOnline = await _connectivity.isOnline();
    if (!isOnline) {
      debugPrint('[SyncService] pullFinancialsForCustomer: offline, skip');
      return 0;
    }

    try {
      debugPrint('[SyncService] pullFinancialsForCustomer($customerId): requesting...');
      final response = await _dio.get(
        '/api/sync/financials',
        queryParameters: {'customerId': customerId},
      );

      debugPrint('[SyncService] pullFinancialsForCustomer: status=${response.statusCode}');
      final data  = response.data as Map<String, dynamic>?;
      final items = data?['financials'] as List? ?? [];
      debugPrint('[SyncService] pullFinancialsForCustomer: ${items.length} títulos recebidos (source=${data?['source']})');

      if (items.isEmpty) return 0;

      final db    = await _db.database;
      final batch = db.batch();
      final now   = DateTime.now().toIso8601String();

      for (final raw in items) {
        final f = raw as Map<String, dynamic>;
        batch.insert('financials', {
          'id':                  _trim(f['id'])?.toString() ?? '',
          'customer_id':         customerId,
          'doc_number':          _trim(f['docNumber']),
          'amount':              _toDouble(f['amount']) ?? 0.0,
          'interest':            _toDouble(f['interest']) ?? 0.0,
          'due_date':            _trim(f['dueDate']),
          'payment_species_id':  _trim(f['paymentSpeciesId']),
          'is_paid':             (f['isPaid'] as bool? ?? false) ? 1 : 0,
          'type':                _trim(f['type']),
          'payment_date':        _trim(f['paymentDate']),
          'last_synced_at':      now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      await batch.commit(noResult: true);
      debugPrint('[SyncService] pullFinancialsForCustomer: ${items.length} títulos salvos no SQLite');
      return items.length;
    } catch (e) {
      debugPrint('[SyncService] pullFinancialsForCustomer ERROR: $e');
      return 0;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PULL — Performance KPIs do ERP (MINHASVENDAS)
  // ─────────────────────────────────────────────────────────────────────────

  /// Baixa KPIs reais de desempenho do vendedor via stored procedures do ERP.
  ///
  /// Chama GET /api/sync/performance?sellerId=X e grava no SQLite.
  /// Os dados vêm das procedures MINHASVENDAS e MINHASVENDASR do Firebird.
  ///
  /// @param sellerId  ID do vendedor no ERP (FUNCIONARIOS.ID_FUNCIONARIO).
  /// Baixa KPIs de performance do vendedor via middleware e persiste no SQLite.
  ///
  /// Estratégia "VPS First":
  /// - Sempre busca do VPS quando online
  /// - Usa deptoId retornado pela API como chave SQLite (estável, independente de
  ///   config local — funciona mesmo após reinstalação ou clear de cache)
  /// - Armazena o deptoId em SharedPreferences para leitura offline
  ///
  /// @returns [SellerKpis] se sucesso, null se falhou (offline ou erro)
  Future<SellerKpis?> pullPerformanceAndReturn(String sellerId, {bool forceRefresh = false}) async {
    if (!await _connectivity.isOnline()) return null;

    try {
      debugPrint('[SyncService] pullPerformance sellerId=$sellerId forceRefresh=$forceRefresh');

      final now = DateTime.now();
      final response = await _dio.get('/api/sync/performance', queryParameters: {
        'sellerId': sellerId,
        'month': now.month,
        'year': now.year,
        if (forceRefresh) 'forceRefresh': 'true',
      });

      final body = response.data;
      if (body == null || body['data'] == null) {
        debugPrint('[SyncService] pullPerformance: resposta vazia');
        return null;
      }

      final data = body['data'] as Map<String, dynamic>;

      // [FIX VPS-FIRST] Usa deptoId retornado pela API como chave SQLite.
      // Motivo: o deptoId é estável e vem do ERP (branchId pode ser null em devices
      // sem SharedPreferences configuradas pelo Configurator — reinstalação, clear).
      // Garante consistência: Worker envia deptoId=X → API retorna deptoId=X →
      // SQLite[deptoId=X] → UI mostra dados da filial X.
      final deptoId  = (data['deptoId'] as num?)?.toInt() ?? 1;
      final companyId = deptoId.toString();

      // Persiste deptoId em SharedPreferences para uso offline
      final prefs = await GetIt.I<AppConfigService>().getPrefsForCache();
      if (prefs != null) await prefs.setInt('cached_depto_id', deptoId);

      // Salva no SQLite
      await _db.upsertSellerKpis({
        'company_id':         companyId,
        'seller_id':          sellerId,
        'month':              (data['month'] as num?)?.toInt() ?? now.month,
        'year':               (data['year'] as num?)?.toInt() ?? now.year,
        'venda_diaria':       (data['vendaDiaria'] as num?)?.toDouble() ?? 0,
        'venda_mensal':       (data['vendaMensal'] as num?)?.toDouble() ?? 0,
        'comissao_diaria':    (data['comissaoDiaria'] as num?)?.toDouble() ?? 0,
        'comissao_mensal':    (data['comissaoMensal'] as num?)?.toDouble() ?? 0,
        'meta_diaria':        (data['metaDiaria'] as num?)?.toDouble() ?? 0,
        'meta_mensal':        (data['metaMensal'] as num?)?.toDouble() ?? 0,
        'servico_mensal':     (data['servicoMensal'] as num?)?.toDouble() ?? 0,
        'comissao_sv_mensal': (data['comissaoSvMensal'] as num?)?.toDouble() ?? 0,
        'total_diario':       (data['totalDiario'] as num?)?.toDouble() ?? 0,
        'total_mensal':       (data['totalMensal'] as num?)?.toDouble() ?? 0,
        'comissao_diaria_r':  (data['comissaoDiariaR'] as num?)?.toDouble() ?? 0,
        'comissao_mensal_r':  (data['comissaoMensalR'] as num?)?.toDouble() ?? 0,
        'synced_at':          data['syncedAt']?.toString() ?? now.toIso8601String(),
      });

      // Retorna objeto diretamente (sem segunda busca no SQLite)
      final kpis = SellerKpis.fromApi(data);
      debugPrint('[SyncService] pullPerformance OK — deptoId=$deptoId vendaMensal=${data["vendaMensal"]}');
      return kpis;
    } on DioException catch (e) {
      debugPrint('[SyncService] pullPerformance DioError: ${e.response?.statusCode} ${e.message}');
      return null;
    } catch (e) {
      debugPrint('[SyncService] pullPerformance ERROR: $e');
      return null;
    }
  }

  /// Compat: mesma lógica mas retorna bool (usado por AutoSyncService).
  Future<bool> pullPerformance(String sellerId, {bool forceRefresh = false}) async {
    final result = await pullPerformanceAndReturn(sellerId, forceRefresh: forceRefresh);
    return result != null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PULL — Sales Rankings do ERP (L_VENDAS_*)
  // ─────────────────────────────────────────────────────────────────────────

  /// Baixa rankings de vendas reais do vendedor via views do ERP.
  ///
  /// Chama GET /api/sync/sales-rankings?sellerId=X e grava no SQLite.
  /// Os dados vêm das views L_VENDAS_PRODUTO, L_VENDAS_CLIENTE, L_VENDAS_REGIAO.
  ///
  /// @param sellerId  ID do vendedor no ERP (FUNCIONARIOS.ID_FUNCIONARIO).
  /// @returns true se os dados foram recebidos com sucesso.
  /// [DIAG] Último diagnóstico do pullSalesRankings (temporário, remover)
  String _lastRankingsDiag = '';
  String get lastRankingsDiag => _lastRankingsDiag;

  Future<bool> pullSalesRankings(String sellerId, {String period = 'month'}) async {
    if (!await _connectivity.isOnline()) return false;

    try {
      debugPrint('[SyncService] pullSalesRankings sellerId=$sellerId period=$period');

      final now = DateTime.now();
      final response = await _dio.get('/api/sync/sales-rankings', queryParameters: {
        'sellerId': sellerId,
        'month': now.month,
        'year': now.year,
        'period': period,
      });

      final body = response.data;
      final source = body?['source']?.toString() ?? '?';
      
      if (body == null || body['data'] == null) {
        _lastRankingsDiag = 'HTTP ${response.statusCode} src=$source data=NULL';
        debugPrint('[SyncService] pullSalesRankings: resposta vazia — $_lastRankingsDiag');
        return false;
      }

      final data = body['data'] as Map<String, dynamic>;
      final topProducts  = data['topProducts']  as List<dynamic>? ?? [];
      final topClients   = data['topClients']   as List<dynamic>? ?? [];
      final byRegion     = data['byRegion']     as List<dynamic>? ?? [];
      final bySeller     = data['bySeller']     as List<dynamic>? ?? [];
      final revenueByDay = data['revenueByDay'] as List<dynamic>? ?? [];
      final clientHealth = data['clientHealth'] as Map<String, dynamic>? ?? {};
      final categoryMix  = data['categoryMix']  as List<dynamic>? ?? [];
      final heatmapStats = data['heatmapStats'] as List<dynamic>? ?? [];

      // [FIX VPS-FIRST] Usa cachedDeptoId como chave SQLite — consistente com pullPerformance.
      // Se não tiver cache ainda (primeira vez), usa '1' (PIVETA DIST padrão).
      final prefs    = await GetIt.I<AppConfigService>().getPrefsForCache();
      final deptoId  = prefs?.getInt('cached_depto_id') ?? 1;
      final companyId = deptoId.toString();

      // Salva no SQLite
      await _db.upsertSalesRankings({
        'company_id':          companyId,
        'seller_id':           sellerId,
        'period':              period,
        'month':               (data['month'] as num?)?.toInt() ?? now.month,
        'year':                (data['year'] as num?)?.toInt() ?? now.year,
        'top_products_json':   _jsonEncode(topProducts),
        'top_clients_json':    _jsonEncode(topClients),
        'by_region_json':      _jsonEncode(byRegion),
        'by_seller_json':      _jsonEncode(bySeller),
        'revenue_by_day_json': _jsonEncode(revenueByDay),
        'client_health_json':  _jsonEncode(clientHealth),
        'category_mix_json':   _jsonEncode(categoryMix),
        'heatmap_stats_json':  _jsonEncode(heatmapStats),
        'synced_at':           data['syncedAt']?.toString() ?? now.toIso8601String(),
      });

      _lastRankingsDiag = 'OK P=${topProducts.length} C=${topClients.length} R=${byRegion.length}';
      debugPrint('[SyncService] pullSalesRankings OK — '
          'produtos=${topProducts.length} clientes=${topClients.length} '
          'regiões=${byRegion.length} revenueByDay=${revenueByDay.length} '
          'categoryMix=${categoryMix.length} heatmap=${heatmapStats.length}');
      return true;
    } on DioException catch (e) {
      _lastRankingsDiag = 'DIO ${e.response?.statusCode ?? "?"}: ${e.message?.substring(0, 80) ?? "?"}';
      debugPrint('[SyncService] pullSalesRankings DioError: ${e.response?.statusCode} ${e.message}');
      return false;
    } catch (e) {
      _lastRankingsDiag = 'ERR: ${e.toString().substring(0, 80)}';
      debugPrint('[SyncService] pullSalesRankings ERROR: $e');
      return false;
    }
  }

  /// Consulta rankings on-demand para um intervalo de datas arbitrário.
  ///
  /// Chama GET /api/sync/rankings-ondemand (Middleware → Firebird direto).
  /// O resultado NÃO é persistido no SQLite — dado efêmero para período personalizado.
  ///
  /// @param sellerId  ID do vendedor.
  /// @param dateFrom  Data inicial ISO 8601 (yyyy-MM-dd).
  /// @param dateTo    Data final ISO 8601 (yyyy-MM-dd).
  /// @returns [SalesRankings] ou null em caso de erro.
  Future<Map<String, dynamic>?> pullRankingsOnDemand(
    String sellerId, {
    required String dateFrom,
    required String dateTo,
  }) async {
    try {
      debugPrint('[SyncService] pullRankingsOnDemand sellerId=$sellerId from=$dateFrom to=$dateTo');

      final response = await _dio.get('/api/sync/rankings-ondemand', queryParameters: {
        'sellerId': sellerId,
        'dateFrom': dateFrom,
        'dateTo': dateTo,
      });

      final body = response.data;
      if (body == null || body['data'] == null) {
        debugPrint('[SyncService] pullRankingsOnDemand: resposta vazia');
        return null;
      }

      debugPrint('[SyncService] pullRankingsOnDemand OK src=${body['source']}');
      return body['data'] as Map<String, dynamic>;
    } on DioException catch (e) {
      debugPrint('[SyncService] pullRankingsOnDemand DioError: ${e.response?.statusCode} ${e.message}');
      return null;
    } catch (e) {
      debugPrint('[SyncService] pullRankingsOnDemand ERROR: $e');
      return null;
    }
  }

  String _jsonEncode(dynamic value) {
    try {
      return const JsonEncoder().convert(value);
    } catch (e) {
      debugPrint('[SyncService] _jsonEncode: falha ao serializar ($e) — retornando []');
      return '[]';
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Enfileirar pedido local
  // ─────────────────────────────────────────────────────────────────────────

  /// Adiciona um pedido à fila de sync local.
  /// Chamado imediatamente após o vendedor confirmar o pedido.
  ///
  /// O payload é o JSON completo que será enviado ao middleware.
  Future<void> enqueueOrder(String orderId, Map<String, dynamic> orderPayload) async {
    const uuid = Uuid();
    await _db.enqueueSyncItem({
      'id':          uuid.v4(),
      'entity_type': 'order',
      'entity_id':   orderId,
      'payload':     jsonEncode(orderPayload),
      'sync_status': SyncStatus.pending.name,
      'created_at':  DateTime.now().toIso8601String(),
      'retry_count': 0,
    });
  }


  // ─────────────────────────────────────────────────────────────────────────
  // SYNC — Logo da Empresa
  // Endpoint: GET /api/sync/company-logo
  // Baixa a logo (PNG/JPG) e salva localmente para uso no PDF de pedido.
  // ─────────────────────────────────────────────────────────────────────────

  /// Retorna o `File` da logo cacheada localmente (pode não existir).
  static Future<File> getCompanyLogoFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/company_logo.png');
  }

  /// Baixa a logo da empresa do middleware e salva em disco.
  ///
  /// Retorna `true` se a logo foi salva com sucesso, `false` se não há logo
  /// ou houve erro (falha silenciosa — não interrompe sync).
  ///
  /// Chamado uma vez por ciclo de sync completo pelo AutoSyncService.
  Future<bool> syncCompanyLogo() async {
    try {
      final response = await _dio.get(
        '/api/sync/company-logo',
        options: Options(responseType: ResponseType.bytes),
      );

      if (response.statusCode == 200 && response.data != null) {
        final bytes = response.data as List<int>;
        if (bytes.isNotEmpty) {
          final file = await getCompanyLogoFile();
          await file.writeAsBytes(bytes, flush: true);
          debugPrint('[SyncService] syncCompanyLogo → salva (${bytes.length} bytes)');
          return true;
        }
      }
      return false;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        // Sem logo cadastrada — remove arquivo local se existir
        final file = await getCompanyLogoFile();
        if (await file.exists()) {
          await file.delete();
          debugPrint('[SyncService] syncCompanyLogo → logo removida (404)');
        }
        return false;
      }
      debugPrint('[SyncService] syncCompanyLogo error: ${e.message}');
      return false;
    } catch (e) {
      debugPrint('[SyncService] syncCompanyLogo error: $e');
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers privados
  // ─────────────────────────────────────────────────────────────────────────

  static String? _trim(dynamic value) {
    if (value == null) return null;
    final s = value.toString().trim();
    return s.isEmpty ? null : s;
  }

  /// Remove caracteres especiais DOS/CP850 presentes em nomes do ERP Firebird.
  ///
  /// O Firebird/Coliseu usa caracteres de desenho de caixas (box-drawing)
  /// como separadores visuais no terminal DOS original.
  /// Ex: U+2261 (≡), U+25A0 (■), U+2500-U+257F (box-drawing lines).
  /// Esses são subistituídos por espaço e o resultado é trimado.
  static String? _cleanOemChars(String? value) {
    if (value == null) return null;
    // Remove box-drawing (U+2500-U+257F), block elements (U+2580-U+259F),
    // geometric shapes usados como separadores (≡ U+2261, ■ U+25A0, etc.)
    final cleaned = value
        .replaceAll(RegExp(r'[\u2500-\u259F\u2260-\u2265\u25A0-\u25FF]'), ' ')
        .replaceAll(RegExp(r' {2,}'), ' ')
        .trim();
    return cleaned.isEmpty ? null : cleaned;
  }


  /// Converte num/String para double com segurança.
  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  /// Converte num/String para int com segurança.
  static int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Backoff exponencial
  // ─────────────────────────────────────────────────────────────────────────

  /// Calcula delay de retry: 2^retryCount segundos, máximo [_maxBackoffSeconds].
  static Duration backoffDelay(int retryCount) {
    final seconds = (1 << retryCount).clamp(1, _maxBackoffSeconds);
    return Duration(seconds: seconds);
  }
}




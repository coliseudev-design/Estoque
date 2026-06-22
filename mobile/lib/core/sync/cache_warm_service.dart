/// cache_warm_service.dart — Re-push automático de catálogo ao detectar cache
/// miss no middleware após restart (M2).
///
/// Quando o middleware reinicia, o Redis fica vazio.
/// Este service detecta a resposta `source: 'empty'` do middleware
/// (via header X-Cache-Status ou campo no JSON) e força um re-push
/// de todos os dados do cache local (SQLite) de volta ao middleware.
///
/// Trigger: chamado pelo SyncService após cada pull bem-sucedido
/// se o servidor retornar dados vazios inesperadamente.
library;

import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../database/database_helper.dart';

/// Responsável por detectar cache miss e fazer re-push ao middleware.
class CacheWarmService {
  final DatabaseHelper _db;
  final Dio _dio;

  static const _entities = [
    _EntityConfig('products',           'catalog',          'produtos'),
    _EntityConfig('customers',          'customers',        'clientes'),
    _EntityConfig('sellers',            'sellers',          'vendedores'),
    _EntityConfig('payment_conditions', 'payment-conditions', 'condicoesPagamento'),
    _EntityConfig('natureza_operacao',  'natureza',         'naturezas'),
  ];

  CacheWarmService({required DatabaseHelper db, required Dio dio})
      : _db = db,
        _dio = dio;

  /// Verifica se o middleware retornou cache vazio e, se sim, re-push os dados.
  ///
  /// [entity] — nome da entidade que retornou vazia
  /// [source]  — valor do campo `source` da resposta (esperado: 'empty')
  Future<void> checkAndWarm(String entity, String? source) async {
    if (source != 'empty') return;  // Cache OK, nada a fazer

    debugPrint('[CacheWarm] Cache miss detectado para "$entity" — iniciando re-push...');

    try {
      final config = _entities.firstWhere(
        (e) => e.entity == entity,
        orElse: () => throw StateError('Entidade desconhecida: $entity'),
      );
      await _pushEntity(config);
    } catch (e) {
      debugPrint('[CacheWarm] Erro ao fazer re-push de "$entity": $e');
    }
  }

  /// Faz warming completo de todos os cache locais ao middleware.
  /// Chamado ao iniciar o app após detectar servidor disponível.
  Future<void> warmAll() async {
    debugPrint('[CacheWarm] Iniciando warming completo do cache...');
    for (final config in _entities) {
      try {
        await _pushEntity(config);
      } catch (e) {
        debugPrint('[CacheWarm] Erro em ${config.entity}: $e');
      }
    }
    debugPrint('[CacheWarm] Warming completo finalizado.');
  }

  Future<void> _pushEntity(_EntityConfig config) async {
    final rows = await _db.database.then((db) => db.query(config.table));
    if (rows.isEmpty) return;

    await _dio.post(
      '/api/sync/${config.route}',
      data: jsonEncode({ config.jsonKey: rows }),
      options: Options(headers: {'Content-Type': 'application/json'}),
    );
    debugPrint('[CacheWarm] Re-push de ${rows.length} ${config.entity} concluído.');
  }
}

class _EntityConfig {
  final String entity;   // Nome interno
  final String route;    // Rota middleware /api/sync/{route}
  final String jsonKey;  // Chave no JSON body
  final String table;    // Tabela SQLite local

  const _EntityConfig(this.entity, this.route, this.jsonKey)
      : table = entity;  // Assume que table == entity name
}

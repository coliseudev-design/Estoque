/// Descarrega a fila de leituras e mantém o catálogo local atualizado.
///
/// Regras:
///  - Leitura é registrada PRIMEIRO no SQLite, depois enviada. Queda de rede,
///    app fechado ou bateria acabando não perdem contagem.
///  - Cada leitura tem UUID próprio: reenviar é seguro (a API ignora duplicadas).
///  - A ordem real das leituras é preservada (scanned_at do aparelho).
library;

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../config/app_config.dart';
import '../db/local_db.dart';
import '../session/session_controller.dart';

class SyncNotice {
  final String documentId;
  final String message;
  const SyncNotice(this.documentId, this.message);
}

class SyncService {
  SyncService(this._db, this._api, this._config, this._session);

  final LocalDb _db;
  final ApiClient _api;
  final AppConfig _config;
  final SessionController _session;

  /// Leituras aguardando envio (banner "N leituras não enviadas").
  final pending = ValueNotifier<int>(0);
  final online = ValueNotifier<bool>(true);
  /// Avisos de leituras recusadas pela API (documento reassumido, rodada encerrada).
  final notices = StreamController<SyncNotice>.broadcast();
  /// Contagens confirmadas pela API após um envio (a tela de conferência escuta).
  final confirmed = StreamController<({String documentId, Map<String, dynamic> body})>.broadcast();

  StreamSubscription? _conn;
  Timer? _timer;
  Timer? _catalogTimer;
  final _flushing = <String, Future<void>>{};

  Future<void> start() async {
    await refreshPending();
    _conn = Connectivity().onConnectivityChanged.listen((results) {
      final isOnline = results.any((r) => r != ConnectivityResult.none);
      online.value = isOnline;
      if (isOnline) flushAll();
    });
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => flushAll());
    _catalogTimer = Timer.periodic(const Duration(minutes: 15), (_) => syncCatalog().catchError((_) {}));
  }

  void dispose() {
    _conn?.cancel();
    _timer?.cancel();
    _catalogTimer?.cancel();
  }

  Future<void> refreshPending() async => pending.value = await _db.pendingCount();

  bool get _canSend => _session.isLoggedIn && !_session.sessionExpired && !_session.offline;

  Future<void> flushAll() async {
    if (!_canSend) return;
    for (final id in await _db.documentsWithPending()) {
      await flushDocument(id);
    }
  }

  /// Envia a fila de um documento. Chamadas concorrentes para o mesmo documento são unificadas.
  Future<void> flushDocument(String documentId) {
    if (!_canSend) return Future.value();
    // Bloco com chaves: `=> _flushing.remove(...)` devolveria o próprio Future e o
    // whenComplete ficaria esperando por ele mesmo (finalizar travava para sempre).
    return _flushing[documentId] ??= _flush(documentId).whenComplete(() {
      _flushing.remove(documentId);
    });
  }

  Future<void> _flush(String documentId) async {
    while (true) {
      final rows = await _db.pendingFor(documentId);
      if (rows.isEmpty) break;
      final batch = rows.take(200).toList();
      final ids = [for (final r in batch) r['id'] as String];
      try {
        final res = await _api.post('/v1/documents/$documentId/scans', {
          'events': [
            for (final r in batch)
              {
                'id': r['id'],
                'round': r['round'],
                'barcode': r['barcode'],
                // Código interno digitado não é EAN cadastrado: identifica o produto explicitamente.
                if (r['explicit_product'] == 1) 'productErpId': r['product_id'],
                'qty': r['qty'],
                'origin': r['origin'],
                'scannedAt': r['scanned_at'],
              }
          ],
        });
        await _db.removeFromOutbox(ids);
        online.value = true;
        final rejected = (res?['rejected'] as List?) ?? const [];
        if (rejected.isNotEmpty) {
          notices.add(SyncNotice(documentId,
              '${rejected.length} leitura(s) descartada(s): a rodada de contagem já tinha sido encerrada.'));
        }
        if (res != null) confirmed.add((documentId: documentId, body: res));
      } on ApiException catch (e) {
        if (e.isNetwork) {
          online.value = false;
          await _db.markAttempt(ids, e.message);
          break;
        }
        if (e.isAuth) break; // sessão expirou: fila espera novo login
        if (e.status == 409 || e.status == 404) {
          // Documento reassumido por outro operador, finalizado ou cancelado:
          // estas leituras não podem mais ser aplicadas.
          await _db.removeFromOutbox([for (final r in rows) r['id'] as String]);
          notices.add(SyncNotice(documentId, 'Leituras não aplicadas: ${e.message}'));
          break;
        }
        // 400 (dado inválido): isola o lote para não travar a fila inteira.
        await _db.markAttempt(ids, e.message);
        await _db.removeFromOutbox(ids);
        notices.add(SyncNotice(documentId, 'Leituras recusadas pela API: ${e.message}'));
      }
    }
    await refreshPending();
  }

  // ── Catálogo (delta) ─────────────────────────────────────────────────────

  Future<void> syncCatalog() async {
    if (!_canSend) return;
    for (final entity in ['products', 'barcodes']) {
      var guard = 0;
      while (guard++ < 500) {
        final cursor = _config.cursor(entity).split('|');
        final res = await _api.get('/v1/catalog/delta', query: {
          'entity': entity,
          if (cursor.length == 2 && cursor[0].isNotEmpty) 'since': cursor[0],
          if (cursor.length == 2 && cursor[1].isNotEmpty) 'after': cursor[1],
          'limit': 2000,
        });
        final items = [for (final i in (res['items'] as List? ?? const [])) Map<String, dynamic>.from(i as Map)];
        if (entity == 'products') {
          await _db.upsertProducts(items);
        } else {
          await _db.upsertBarcodes(items);
        }
        final next = res['next'] as Map?;
        if (next != null) await _config.setCursor(entity, '${next['since']}|${next['after']}');
        if (res['done'] == true || items.isEmpty) break;
      }
    }
  }
}

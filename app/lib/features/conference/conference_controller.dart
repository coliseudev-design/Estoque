/// Estado de uma conferência em andamento.
///
/// Fluxo de uma leitura:
///   1. resolve o código localmente (itens do documento → catálogo offline)
///   2. grava no SQLite (outbox) — a partir daqui a leitura não se perde
///   3. atualiza a tela na hora (contagem otimista)
///   4. envia para a API em segundo plano; a resposta corrige a contagem
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../core/api/api_client.dart';
import '../../core/db/local_db.dart';
import '../../core/sync/sync_service.dart';
import '../../models/models.dart';

enum ScanOutcome { counted, extra, notInRecount, unknown }

class ScanFeedback {
  final ScanOutcome outcome;
  final String code;
  final String title;
  final String detail;
  final String eventId;
  const ScanFeedback(this.outcome, this.code, this.title, this.detail, this.eventId);
  bool get isError => outcome == ScanOutcome.unknown || outcome == ScanOutcome.notInRecount;
}

class ConferenceController extends ChangeNotifier {
  ConferenceController(this.documentId, this._api, this._db, this._sync) {
    _confirmedSub = _sync.confirmed.stream.where((c) => c.documentId == documentId).listen(_onConfirmed);
  }

  final String documentId;
  final ApiClient _api;
  final LocalDb _db;
  final SyncService _sync;
  late final StreamSubscription _confirmedSub;

  DocDetail? detail;
  bool loading = true;
  bool offlineMode = false;
  String? error;
  ScanFeedback? last;
  final List<ScanFeedback> history = [];

  Map<String, double> _serverCounts = {};
  Map<String, double> _pendingUnits = {};
  final Map<String, String> _names = {};

  int get round => detail?.header.round ?? 0;
  bool get isRecount => round > 0;

  /// Contado na rodada = confirmado pela API + ainda na fila.
  Map<String, double> get counts {
    final all = {..._serverCounts};
    _pendingUnits.forEach((k, v) => all[k] = (all[k] ?? 0) + v);
    all.removeWhere((_, v) => v == 0);
    return all;
  }

  String nameOf(String productId) =>
      _names[productId] ??
      detail?.items.where((i) => i.productErpId == productId).firstOrNull?.description ??
      productId;

  // ── Carga ────────────────────────────────────────────────────────────────

  Future<void> open() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final json = await _api.post('/v1/documents/$documentId/claim', {});
      await _apply(json!);
      await _db.cacheDocument(documentId, jsonEncode(json));
      offlineMode = false;
    } on ApiException catch (e) {
      if (!e.isNetwork) {
        error = e.message;
      } else {
        // Sem rede: só continua o que já estava reservado para este operador.
        final cached = await _db.cachedDocument(documentId);
        final map = cached == null ? null : jsonDecode(cached) as Map<String, dynamic>;
        if (map != null && (map['lock']?['mine'] == true)) {
          await _apply(map);
          offlineMode = true;
        } else {
          error = 'Sem conexão. Só é possível continuar offline uma conferência que você já tinha iniciado neste aparelho.';
        }
      }
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> _apply(Map<String, dynamic> json) async {
    detail = DocDetail.fromJson(json);
    for (final i in detail!.items) {
      _names[i.productErpId] = i.description;
    }
    _serverCounts = Map.of(detail!.counts);
    await _refreshPending();
  }

  Future<void> _refreshPending() async {
    _pendingUnits = await _db.pendingUnits(documentId, round);
  }

  Future<void> _onConfirmed(({String documentId, Map<String, dynamic> body}) c) async {
    final body = c.body;
    if (body['round'] != round) return;
    _serverCounts = {
      for (final e in ((body['counts'] as Map?) ?? const {}).entries) e.key as String: parseQty(e.value),
    };
    if (detail != null) {
      detail = DocDetail(
        header: detail!.header,
        items: detail!.items,
        barcodes: detail!.barcodes,
        counts: _serverCounts,
        unknownScans: [for (final u in (body['unknownScans'] as List? ?? const [])) UnknownScan.fromJson(u)],
        recount: detail!.recount,
        settings: detail!.settings,
      );
    }
    await _refreshPending();
    offlineMode = false;
    notifyListeners();
  }

  // ── Leitura ──────────────────────────────────────────────────────────────

  Future<ScanFeedback> scan(String rawCode, {int packs = 1, required String origin}) async {
    final code = rawCode.trim();
    final d = detail!;

    // 1) códigos do próprio documento  2) catálogo offline
    String? productId;
    double factor = 1;
    bool explicitProduct = false;
    final docCode = d.barcodes[code];
    if (docCode != null) {
      productId = docCode.productErpId;
      factor = docCode.factor;
    } else if (d.items.any((i) => i.productErpId == code)) {
      // Código interno de um item do documento digitado à mão.
      productId = code;
      explicitProduct = true;
    } else {
      final local = await _db.resolve(code);
      if (local != null) {
        productId = local.productErpId;
        factor = local.factor;
        explicitProduct = local.productErpId == code && !(await _isKnownBarcode(code));
        if (local.description.isNotEmpty) _names[productId] = local.description;
      }
    }

    final eventId = const Uuid().v4();
    final units = packs * factor;
    await _db.enqueue({
      'id': eventId,
      'document_id': documentId,
      'round': round,
      'barcode': code,
      'product_id': productId,
      'explicit_product': explicitProduct ? 1 : 0,
      'qty': packs,
      'units': units,
      'origin': origin,
      'scanned_at': DateTime.now().toUtc().toIso8601String(),
    });
    await _refreshPending();

    final ScanFeedback fb;
    if (productId == null) {
      fb = ScanFeedback(ScanOutcome.unknown, code, 'Código não cadastrado', '$code — toque em desfazer ou confira a etiqueta', eventId);
    } else if (isRecount && !d.recount.contains(productId)) {
      fb = ScanFeedback(ScanOutcome.notInRecount, code, nameOf(productId),
          'Este produto não está na recontagem — a leitura será ignorada', eventId);
    } else {
      final inDoc = d.items.isEmpty || d.items.any((i) => i.productErpId == productId);
      final pack = factor != 1 ? ' (embalagem com ${_fmt(factor)})' : '';
      fb = ScanFeedback(inDoc ? ScanOutcome.counted : ScanOutcome.extra, code, nameOf(productId),
          '+${_fmt(units)}$pack · total ${_fmt(counts[productId] ?? units)}${inDoc ? '' : ' · fora do documento'}', eventId);
    }
    last = fb;
    history.insert(0, fb);
    if (history.length > 30) history.removeLast();
    notifyListeners();

    unawaited(_sync.flushDocument(documentId));
    return fb;
  }

  Future<bool> _isKnownBarcode(String code) async {
    final r = await _db.db.query('barcodes', where: 'barcode = ?', whereArgs: [code], limit: 1);
    return r.isNotEmpty;
  }

  /// Desfaz uma leitura: se ainda está na fila, some; se já foi enviada, estorna na API.
  Future<void> undo(String eventId) async {
    final queued = await _db.db.query('outbox', where: 'id = ?', whereArgs: [eventId], limit: 1);
    if (queued.isNotEmpty) {
      await _db.removeFromOutbox([eventId]);
      await _sync.refreshPending();
    } else {
      await _api.post('/v1/documents/$documentId/scans/$eventId/void');
      await reload();
    }
    history.removeWhere((h) => h.eventId == eventId);
    if (last?.eventId == eventId) last = null;
    await _refreshPending();
    notifyListeners();
  }

  Future<void> reload() async {
    final json = await _api.get('/v1/documents/$documentId');
    await _apply(json);
    await _db.cacheDocument(documentId, jsonEncode(json));
    notifyListeners();
  }

  // ── Fechamento ───────────────────────────────────────────────────────────

  Future<FinalizeResult> finalize() async {
    await _sync.flushDocument(documentId);
    if ((await _db.pendingFor(documentId)).isNotEmpty) {
      throw const ApiException('Ainda há leituras não enviadas. Conecte-se à internet para finalizar — nada foi perdido.');
    }
    final res = FinalizeResult.fromJson((await _api.post('/v1/documents/$documentId/finalize'))!);
    if (res.status == 'DIVERGENTE') {
      history.clear();
      last = null;
      await reload();
    }
    return res;
  }

  Future<void> release() => _api.post('/v1/documents/$documentId/release');

  @override
  void dispose() {
    _confirmedSub.cancel();
    super.dispose();
  }

  static String _fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(3).replaceAll(RegExp(r'0+$'), '');
}

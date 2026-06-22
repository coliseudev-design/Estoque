/// AutoSyncService — Sincronização automática em background.
///
/// Dois triggers:
/// 1. Periódico: Timer.periodic a cada 15 minutos
/// 2. Reconexão: disparo imediato ao detectar online após offline
///
/// REGRA (Rule-02 Async): todas as operações são async, sem bloqueio.
/// REGRA: mutex `_isSyncing` previne sync duplo (triggered concorrente).
library;

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'connectivity_service.dart';
import '../sync/sync_service.dart';
import '../session/session_service.dart';

/// Estado do AutoSyncService para feedback na UI.
enum AutoSyncState {
  /// Inativo — aguardando próximo trigger.
  idle,

  /// Sincronização em andamento.
  syncing,

  /// Última sync concluída com sucesso.
  success,

  /// Última sync encerrou com erros (parciais ou totais).
  partial,
}

class AutoSyncService {
  final SyncService         _sync;
  final ConnectivityService _connectivity;
  final SessionService?     _session;

  static const Duration _interval = Duration(minutes: 5);

  Timer?                     _periodicTimer;
  Timer?                     _fastPollTimer;
  StreamSubscription<ConnectivityStatus>? _connectivitySub;
  bool                       _isSyncing   = false;
  bool                       _pendingRetry = false;
  ConnectivityStatus         _lastStatus = ConnectivityStatus.offline;

  /// Notifier público — a UI pode observar sem polling.
  final ValueNotifier<AutoSyncState> stateNotifier =
      ValueNotifier(AutoSyncState.idle);

  AutoSyncService({
    required SyncService         sync,
    required ConnectivityService connectivity,
    SessionService?              session,
  })  : _sync         = sync,
       _connectivity = connectivity,
       _session      = session;

  // ─────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────

  /// Inicia os dois triggers de sync automático.
  /// Chamar uma vez após setupLocator().
  void start() {
    _lastStatus = _connectivity.currentStatus;

    // Trigger 1 — Periódico (a cada 15min)
    _periodicTimer = Timer.periodic(_interval, (_) => _trySync());

    // Trigger de Polling Rápido (a cada 10s para erpOrderId)
    _fastPollTimer = Timer.periodic(const Duration(seconds: 10), (_) => _fastPollStatuses());

    // Trigger 2 — Reconexão (offline → online)
    _connectivitySub = _connectivity.status.listen((status) {
      final wasOffline = _lastStatus == ConnectivityStatus.offline;
      final isNowOnline = status == ConnectivityStatus.online;
      _lastStatus = status;

      if (wasOffline && isNowOnline) {
        debugPrint('[AutoSync] Reconexão detectada (offline → online). Aguardando rede estabilizar...');
        // Delay para deixar DNS/rotas estabilizarem antes de tentar sync
        _onReconnect();
      }
    });
  }

  /// Trata reconexão: envia pedidos pendentes DIRETAMENTE (sem mutex),
  /// depois dispara sync completo para pulls.
  Future<void> _onReconnect() async {
    // Espera a rede estabilizar (DNS, rotas, etc.)
    await Future.delayed(const Duration(seconds: 3));

    // Verifica se ainda está online após delay
    if (!await _connectivity.isOnline()) {
      debugPrint('[AutoSync] Rede perdida durante delay. Abortando.');
      return;
    }

    // PUSH DIRETO — bypassa o mutex _isSyncing para garantir envio imediato
    debugPrint('[AutoSync] Reconexão: enviando pedidos pendentes diretamente...');
    try {
      final result = await _sync.syncPendingOrders();
      debugPrint('[AutoSync] Reconexão push: $result');
    } catch (e) {
      debugPrint('[AutoSync] Reconexão push falhou: $e');
    }

    try {
      await _sync.pushLocalCustomers();
    } catch (e) {
      debugPrint('[AutoSync] Reconexão pushCustomers falhou: $e');
    }

    // Depois faz o ciclo completo (pulls) quando o mutex liberar
    debugPrint('[AutoSync] Reconexão: disparando sync completo para pulls...');
    _trySync();
  }

  /// Para todos os timers e subscriptions.
  void stop() {
    _periodicTimer?.cancel();
    _fastPollTimer?.cancel();
    _connectivitySub?.cancel();
  }

  /// Polling rápido isolado apenas para buscar números de ERP (erpOrderId).
  Future<void> _fastPollStatuses() async {
    if (_isSyncing) return;
    if (!await _connectivity.isOnline()) return;

    try {
      final updated = await _sync.pullOrderStatuses();
      if (updated > 0) {
        // Notifica a UI que houve alteração (ex: HomeScreen recarregar pedidos)
        stateNotifier.value = AutoSyncState.success;
        // Força trigger listeners mesmo se valor não mudou
        stateNotifier.notifyListeners();
      }
    } catch (_) {}
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Sync com mutex
  // ─────────────────────────────────────────────────────────────────────────

  /// Tenta executar sync se online e não estiver já sincronizando.
  ///
  /// Protegido por mutex `_isSyncing` — chamadas concorrentes são ignoradas
  /// silenciosamente (não enfileiradas).
  ///
  /// [isRetry]: quando true, faz apenas push de pedidos pendentes (sem pulls),
  /// para enviar rapidamente pedidos recém-enfileirados.
  Future<void> _trySync({bool isRetry = false, bool isManual = false}) async {
    if (_isSyncing) return;
    if (!await _connectivity.isOnline()) return;

    _isSyncing = true;
    stateNotifier.value = AutoSyncState.syncing;

    try {
      final pushResult = await _sync.syncPendingOrders();

      Map<String, int> pushCustResult = {'errors': 0};
      try {
        pushCustResult = await _sync.pushLocalCustomers();
      } catch (e) {
        debugPrint('[AutoSync] Erro em pushLocalCustomers: $e');
        pushCustResult = {'errors': 1};
      }

      // No retry, pula os pulls — faz apenas push rápido de pedidos pendentes
      if (!isRetry) {
        // Cada pull isolado — falha de um NÃO impede os demais
        for (final pull in <MapEntry<String, Future<int> Function()>>[
          MapEntry('CompanySettings', _sync.pullCompanySettings),
          MapEntry('PaymentSpecies',  _sync.pullPaymentSpecies),
          MapEntry('PaymentCondition',_sync.pullPaymentConditions),
          MapEntry('Natureza',        _sync.pullNatureza),
          MapEntry('Sellers',         _sync.pullSellers),
          MapEntry('OrderStatuses',   _sync.pullOrderStatuses),
          MapEntry('Catalog',         _sync.pullCatalog),
          MapEntry('Customers',       _sync.pullCustomers),
          MapEntry('PriceTables',     _sync.pullPriceTables),
          MapEntry('Financials',      _sync.pullFinancials),
          MapEntry('HistoricalOrders', () async {
            final sellerId = _session?.activeSession?.sellerId;
            if (sellerId != null && sellerId.isNotEmpty) {
              return await _sync.pullHistoricalOrders(sellerId);
            }
            return 0;
          }),
        ]
        ) {
          try {
            await pull.value();
          } catch (e) {
            debugPrint('[AutoSync] Erro em ${pull.key}: $e');
          }
        }

        // Pull de KPIs de desempenho reais do ERP (MINHASVENDAS)
        try {
          final sellerId = _session?.activeSession?.sellerId;
          if (sellerId != null && sellerId.isNotEmpty) {
            await _sync.pullPerformance(sellerId, forceRefresh: isManual);
            // Pull rankings para TODOS os períodos (today/week/month/all)
            for (final p in ['today', 'week', 'month', 'all']) {
              await _sync.pullSalesRankings(sellerId, period: p);
            }
          }
        } catch (e) {
          debugPrint('[AutoSync] Erro em pullPerformance/Rankings: $e');
        }

        // Sync logo da empresa (para PDF de pedido)
        try {
          await _sync.syncCompanyLogo();
        } catch (e) {
          debugPrint('[AutoSync] Erro em syncCompanyLogo: $e');
        }
      }

      final hasErrors = (pushResult['errors'] ?? 0) > 0 || (pushCustResult['errors'] ?? 0) > 0;
      stateNotifier.value =
          hasErrors ? AutoSyncState.partial : AutoSyncState.success;
    } catch (_) {
      stateNotifier.value = AutoSyncState.partial;
    } finally {
      _isSyncing = false;

      // Se um triggerManual() foi chamado durante o sync,
      // re-executa imediatamente para enviar pedidos recém-enfileirados.
      if (_pendingRetry) {
        _pendingRetry = false;
        debugPrint('[AutoSync] Retry pendente detectado — re-executando sync para pedidos recentes.');
        _trySync(isRetry: true);
      }
    }
  }

  /// Disparo manual — ex: botão de refresh na UI ou após confirmar pedido.
  /// Se outra sync está em andamento, agenda re-execução imediata ao terminar.
  Future<void> triggerManual() async {
    if (_isSyncing) {
      // Marca para re-executar ao final do sync atual
      _pendingRetry = true;
      debugPrint('[AutoSync] Sync em andamento — agendando retry ao terminar.');
      return;
    }
    return _trySync(isManual: true);
  }
}

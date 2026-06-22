/// ConnectivityStatusBar — Widget persistente de status de sincronização.
///
/// Sempre visível no topo da tela. Informa o vendedor sobre:
/// - Estado da conexão (online/offline)
/// - Pedidos pendentes de envio
/// - Pedidos com erro de sync
/// - Botão de sync manual
///
/// REGRA UX: Este widget deve ser o PRIMEIRO elemento informativo que o
/// vendedor vê ao abrir qualquer tela principal. A ausência deste feedback
/// é a causa #1 de pedidos duplicados e retrabalho em campo.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/network/auto_sync_service.dart';
import '../../../core/network/connectivity_service.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_typography.dart';
import '../../../core/sync/sync_service.dart';

/// Dados de estado para o status bar.
class _StatusBarState {
  final ConnectivityStatus connectivity;
  final int pendingCount;
  final int errorCount;
  final bool isSyncing;
  final DateTime? lastSyncAt;

  // UX 1: contadores do cache local (exibidos no modo offline)
  final int productCount;
  final int customerCount;

  const _StatusBarState({
    required this.connectivity,
    required this.pendingCount,
    required this.errorCount,
    required this.isSyncing,
    this.lastSyncAt,
    this.productCount  = 0,
    this.customerCount = 0,
  });
}

class ConnectivityStatusBar extends StatefulWidget {
  final SyncService syncService;
  final ConnectivityService connectivityService;
  final DatabaseHelper dbHelper;

  /// [AutoSyncService] para disparar ciclo completo de sync manual.
  /// Se não fornecido, o botão de refresh dispara apenas push+pull básico.
  final AutoSyncService? autoSyncService;

  /// Callback opcional quando o usuário toca em "Ver erros"
  final VoidCallback? onErrorTap;

  const ConnectivityStatusBar({
    super.key,
    required this.syncService,
    required this.connectivityService,
    required this.dbHelper,
    this.autoSyncService,
    this.onErrorTap,
  });

  @override
  State<ConnectivityStatusBar> createState() => _ConnectivityStatusBarState();
}

class _ConnectivityStatusBarState extends State<ConnectivityStatusBar> {
  _StatusBarState _state = const _StatusBarState(
    connectivity: ConnectivityStatus.offline,
    pendingCount: 0,
    errorCount:   0,
    isSyncing:    false,
  );

  StreamSubscription<ConnectivityStatus>? _connectivitySub;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshCounts();
    // Escuta mudanças de conectividade
    _connectivitySub = widget.connectivityService.status.listen((_) {
      _refreshCounts();
    });
    // Refresh periódico a cada 30s
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) => _refreshCounts());

    // Sincroniza isSyncing com o AutoSyncService (evita estado travado)
    widget.autoSyncService?.stateNotifier.addListener(_onAutoSyncChanged);
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _refreshTimer?.cancel();
    widget.autoSyncService?.stateNotifier.removeListener(_onAutoSyncChanged);
    super.dispose();
  }

  /// Atualiza isSyncing e refresh dos contadores quando AutoSync muda de estado.
  void _onAutoSyncChanged() {
    if (!mounted) return;
    final autoState = widget.autoSyncService?.stateNotifier.value;
    final nowSyncing = autoState == AutoSyncState.syncing;
    final finished   = autoState == AutoSyncState.success ||
                       autoState == AutoSyncState.partial;

    setState(() {
      _state = _StatusBarState(
        connectivity:  _state.connectivity,
        pendingCount:  _state.pendingCount,
        errorCount:    _state.errorCount,
        isSyncing:     nowSyncing,
        lastSyncAt:    finished ? DateTime.now() : _state.lastSyncAt,
        productCount:  _state.productCount,
        customerCount: _state.customerCount,
      );
    });

    if (finished) _refreshCounts();
  }

  Future<void> _refreshCounts() async {
    final pendingItems = await widget.dbHelper.getSyncQueue('pending');
    final errorItems   = await widget.dbHelper.getSyncQueue('error');
    final connectivity = widget.connectivityService.currentStatus;

    // UX 1: contadores do cache local (consultados sempre, não só offline)
    final db = await widget.dbHelper.database;
    final pRows = await db.rawQuery('SELECT COUNT(*) AS total FROM products');
    final cRows = await db.rawQuery('SELECT COUNT(*) AS total FROM customers');
    final productCount  = (pRows.first['total'] as int? ?? 0);
    final customerCount = (cRows.first['total'] as int? ?? 0);

    if (!mounted) return;
    setState(() {
      _state = _StatusBarState(
        connectivity:  connectivity,
        pendingCount:  pendingItems.length,
        errorCount:    errorItems.length,
        isSyncing:     _state.isSyncing,
        lastSyncAt:    _state.lastSyncAt,
        productCount:  productCount,
        customerCount: customerCount,
      );
    });
  }

  Future<void> _triggerManualSync() async {
    if (_state.isSyncing) return;
    HapticFeedback.lightImpact();

    setState(() {
      _state = _StatusBarState(
        connectivity:  _state.connectivity,
        pendingCount:  _state.pendingCount,
        errorCount:    _state.errorCount,
        isSyncing:     true,
        lastSyncAt:    _state.lastSyncAt,
        productCount:  _state.productCount,
        customerCount: _state.customerCount,
      );
    });

    // Usa o ciclo completo do AutoSyncService (push + pull tudo)
    // Fallback para sync básico se AutoSyncService não estiver disponível
    if (widget.autoSyncService != null) {
      await widget.autoSyncService!.triggerManual();
    } else {
      await widget.syncService.syncPendingOrders();
      await widget.syncService.pullCatalog();
    }

    setState(() {
      _state = _StatusBarState(
        connectivity:  _state.connectivity,
        pendingCount:  _state.pendingCount,
        errorCount:    _state.errorCount,
        isSyncing:     false,
        lastSyncAt:    DateTime.now(),
        productCount:  _state.productCount,
        customerCount: _state.customerCount,
      );
    });

    await _refreshCounts();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final hasError  = _state.errorCount > 0;
    final isOffline = _state.connectivity == ConnectivityStatus.offline;

    final Color bgColor;
    final Color fgColor;
    final String statusText;
    final Widget leadingIcon;

    if (hasError) {
      // Estado de erro — máxima urgência
      bgColor    = AppColors.syncError;
      fgColor    = Colors.white;
      statusText = 'Erro · ${_state.errorCount} ${_state.errorCount == 1 ? 'pedido' : 'pedidos'} com falha';
      leadingIcon = const Icon(Icons.warning_rounded, size: 16, color: Colors.white);
    } else if (isOffline) {
      // Offline — informativo, não bloqueante
      bgColor = AppColors.syncPending;
      fgColor = Colors.white;
      // UX 1: exibe contadores do cache local
      final hasCache = _state.productCount > 0 || _state.customerCount > 0;
      statusText = _state.pendingCount > 0
          ? 'Offline · ${_state.pendingCount} ${_state.pendingCount == 1 ? 'pedido aguardando' : 'pedidos aguardando'}'
          : hasCache
              ? 'Offline · ${_state.productCount} produtos | ${_state.customerCount} clientes'
              : 'Offline · operando localmente';
      leadingIcon = const Icon(Icons.cloud_off_rounded, size: 16, color: Colors.white);
    } else {
      // Online — status positivo
      bgColor    = AppColors.syncSuccess;
      fgColor    = Colors.white;
      statusText = _buildOnlineText();
      leadingIcon = const Icon(Icons.cloud_done_rounded, size: 16, color: Colors.white);
    }

    return Material(
      color: bgColor,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 36,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                leadingIcon,
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    statusText,
                    style: AppTypography.badge.copyWith(color: fgColor),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

                // Botão "Ver" quando há erros
                if (hasError)
                  GestureDetector(
                    onTap: widget.onErrorTap,
                    child: Text(
                      'Ver →',
                      style: AppTypography.badge.copyWith(
                        color: fgColor,
                        decoration: TextDecoration.underline,
                        decorationColor: fgColor,
                      ),
                    ),
                  ),

                if (hasError) const SizedBox(width: 8),

                // Botão de sync manual
                GestureDetector(
                  onTap: _triggerManualSync,
                  child: _state.isSyncing
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: fgColor,
                          ),
                        )
                      : Icon(Icons.refresh_rounded, size: 18, color: fgColor),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _buildOnlineText() {
    if (_state.isSyncing) return 'Sincronizando...';
    if (_state.pendingCount > 0) {
      return 'Online · ${_state.pendingCount} aguardando sync';
    }
    if (_state.lastSyncAt != null) {
      final diff = DateTime.now().difference(_state.lastSyncAt!);
      if (diff.inMinutes < 1)   return 'Online · sincronizado agora';
      if (diff.inMinutes < 60)  return 'Online · sync há ${diff.inMinutes}min';
      if (diff.inHours < 24)    return 'Online · sync há ${diff.inHours}h';
    }
    return 'Online';
  }
}

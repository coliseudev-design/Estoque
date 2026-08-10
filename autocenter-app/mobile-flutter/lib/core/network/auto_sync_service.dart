import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'sync_queue_service.dart';

class AutoSyncService {
  static final AutoSyncService instance = AutoSyncService._init();
  AutoSyncService._init();

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _periodicTimer;

  void initialize() {
    // 1. Listen to connectivity changes
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      if (results.isNotEmpty && !results.contains(ConnectivityResult.none)) {
        print('[AutoSyncService] Conexão estabelecida/restaurada. Iniciando processamento da fila.');
        SyncQueueService.instance.processQueue();
      }
    });

    // 2. Setup periodic background sync check (every 5 minutes)
    _periodicTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      print('[AutoSyncService] Iniciando sincronização periódica programada.');
      SyncQueueService.instance.processQueue();
    });

    // Run once on startup
    SyncQueueService.instance.processQueue();
  }

  void dispose() {
    _connectivitySubscription?.cancel();
    _periodicTimer?.cancel();
  }
}

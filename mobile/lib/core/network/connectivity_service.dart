/// ConnectivityService — Stream reativo de status de conectividade.
///
/// Emite [ConnectivityStatus] sempre que a conexão mudar.
/// O app nunca "trava" offline — offline é estado normal de operação.
///
/// Uso via GetIt (DI):
///   final connectivity = GetIt.I<ConnectivityService>();
///   connectivity.status.listen((status) { ... });
library;

import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

/// Status de conectividade do dispositivo.
enum ConnectivityStatus {
  /// Conexão ativa (WiFi, dados móveis, ethernet)
  online,

  /// Sem conexão de rede
  offline,
}

class ConnectivityService {
  final Connectivity _connectivity = Connectivity();

  final StreamController<ConnectivityStatus> _controller =
      StreamController<ConnectivityStatus>.broadcast();

  StreamSubscription<List<ConnectivityResult>>? _subscription;

  ConnectivityStatus _currentStatus = ConnectivityStatus.offline;

  /// Status atual (sincronizado — sem await).
  ConnectivityStatus get currentStatus => _currentStatus;

  /// Stream de mudanças de status. É broadcast — pode ter múltiplos listeners.
  Stream<ConnectivityStatus> get status => _controller.stream;

  /// Inicializa o serviço e começa a escutar mudanças de rede.
  /// Deve ser chamado uma vez no startup da aplicação.
  Future<void> initialize() async {
    // Começa assumindo online por padrão para evitar bloqueio preventivo antes de ouvir o stream nativo
    _currentStatus = ConnectivityStatus.online;

    // Escuta mudanças
    _subscription = _connectivity.onConnectivityChanged.listen(
      (results) {
        final newStatus = _mapResults(results);
        if (newStatus != _currentStatus) {
          _currentStatus = newStatus;
          _controller.add(newStatus);
        }
      },
    );

    // Obtém status inicial de forma assíncrona, sem travar o main thread do Flutter/iOS
    _connectivity.checkConnectivity().then((results) {
      final newStatus = _mapResults(results);
      if (newStatus != _currentStatus) {
        _currentStatus = newStatus;
        _controller.add(newStatus);
      }
    }).catchError((_) {});
  }

  /// Mapeia lista de [ConnectivityResult] para [ConnectivityStatus].
  static ConnectivityStatus _mapResults(List<ConnectivityResult> results) {
    if (results.isEmpty) return ConnectivityStatus.offline;
    final hasConnection = results.any((r) => r != ConnectivityResult.none);
    return hasConnection ? ConnectivityStatus.online : ConnectivityStatus.offline;
  }

  /// Verifica em tempo real se há conexão disponível.
  /// Use para validar antes de iniciar uma sync.
  Future<bool> isOnline() async {
    // Retorna o status em cache imediatamente para evitar chamadas bloqueantes de canal nativo
    return _currentStatus == ConnectivityStatus.online;
  }

  /// Libera recursos. Chamar apenas no dispose da aplicação.
  Future<void> dispose() async {
    await _subscription?.cancel();
    await _controller.close();
  }
}

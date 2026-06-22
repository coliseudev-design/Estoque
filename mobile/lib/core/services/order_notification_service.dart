/// order_notification_service.dart — Notificação local quando pedido é
/// confirmado no ERP (M3).
///
/// Polling periódico: verifica pedidos que mudaram de 'pending' para 'synced'
/// desde a última verificação e exibe notificação local com flutter_local_notifications.
///
/// Integração:
///   1. Adicionar ao pubspec.yaml: flutter_local_notifications: ^17.0.0
///   2. Inicializar no main.dart via service_locator
///   3. Chamar startPolling() após autenticação do vendedor
library;

import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Serviço que monitora confirmações de pedidos e dispara notificações locais.
class OrderNotificationService {
  final Dio _dio;
  final FlutterLocalNotificationsPlugin _notifications;

  static const _pollInterval = Duration(seconds: 30);
  static const _channelId    = 'coliseu_orders';
  static const _channelName  = 'Pedidos';

  Timer?   _timer;
  DateTime _lastCheck = DateTime.now();
  bool     _initialized = false;

  OrderNotificationService({required Dio dio})
      : _dio = dio,
        _notifications = FlutterLocalNotificationsPlugin();

  /// Inicializa o plugin de notificações locais.
  Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings     = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _notifications.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    _initialized = true;
    debugPrint('[OrderNotificationService] Inicializado.');

    // Solicita as permissões de forma assíncrona para não bloquear o main thread do iOS
    _requestIosPermissions();
  }

  void _requestIosPermissions() {
    _notifications
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
  }

  /// Inicia o polling de confirmações de pedidos.
  void startPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(_pollInterval, (_) => _checkConfirmedOrders());
    debugPrint('[OrderNotificationService] Polling iniciado (${_pollInterval.inSeconds}s).');
  }

  /// Para o polling (ex: ao fazer logout).
  void stopPolling() {
    _timer?.cancel();
    _timer = null;
    debugPrint('[OrderNotificationService] Polling parado.');
  }

  Future<void> _checkConfirmedOrders() async {
    try {
      final from = _lastCheck.toIso8601String();
      _lastCheck = DateTime.now();

      final res = await _dio.get<Map<String, dynamic>>(
        '/api/orders/pending',
        queryParameters: { 'confirmedSince': from },
      );

      final data   = res.data!;
      final orders = (data['orders'] as List? ?? []);

      // Filtra apenas os recém-confirmados (synced) desde last check
      final confirmed = orders.where((o) => (o['syncStatus'] ?? o['sync_status']) == 'synced').toList();

      for (final order in confirmed) {
        await _showNotification(
          id:    order['id'].hashCode.abs(),
          title: '✅ Pedido confirmado no ERP!',
          body:  'Cliente: ${order['customerName'] ?? 'Desconhecido'} · '
                 'Total: ${_formatCurrency(order['totalAmount'])}',
          payload: order['id']?.toString() ?? '',
        );
      }
    } catch (e) {
      debugPrint('[OrderNotificationService] Erro no polling: $e');
    }
  }

  Future<void> _showNotification({
    required int    id,
    required String title,
    required String body,
    String?         payload,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      _channelId, _channelName,
      importance: Importance.high,
      priority:   Priority.high,
      icon:       '@mipmap/ic_launcher',
    );

    await _notifications.show(
      id, title, body,
      const NotificationDetails(android: androidDetails, iOS: DarwinNotificationDetails()),
      payload: payload,
    );
    debugPrint('[OrderNotificationService] Notificação exibida: $title');
  }

  void _onNotificationTapped(NotificationResponse details) {
    final orderId = details.payload;
    debugPrint('[OrderNotificationService] Notificação tocada, orderId: $orderId');
    // TODO: navegar para tela de detalhes do pedido via NavigationService
  }

  String _formatCurrency(dynamic value) {
    final v = (value is num) ? value.toDouble() : double.tryParse(value?.toString() ?? '0') ?? 0;
    return 'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  void dispose() {
    _timer?.cancel();
  }
}

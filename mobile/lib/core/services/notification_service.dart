/// NotificationService — Notificações locais para o vendedor.
///
/// Responsabilidades:
/// - Inicializar o plugin flutter_local_notifications
/// - Exibir notificação quando um pedido for confirmado no ERP (erpOrderId disponível)
/// - Exibir notificação quando um pedido entrar em estado de erro de integração
///
/// REGRA: Não usa push remoto (FCM/APNs). Funciona 100% offline.
///        O AutoSyncService chama [notifyOrderSynced] e [notifyOrderError]
///        após cada ciclo de pullOrderStatuses().
library;

import 'dart:ui' show Color;
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static const _channelId   = 'coliseu_orders';
  static const _channelName = 'Pedidos Coliseu';
  static const _channelDesc = 'Atualizações de status dos pedidos enviados ao ERP';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  // ── Inicialização ─────────────────────────────────────────────────────────

  /// Inicializa o plugin. Deve ser chamado em [main] antes do runApp.
  Future<void> initialize() async {
    if (kIsWeb) return; // Web não suporta notificações locais

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings     = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const settings = InitializationSettings(
      android: androidSettings,
      iOS:     iosSettings,
    );

    await _plugin.initialize(settings);
    _initialized = true;

    // Solicita as permissões de forma assíncrona para não bloquear o main thread do iOS
    _requestIosPermissions();
  }

  void _requestIosPermissions() {
    _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
  }

  // ── Notificações ──────────────────────────────────────────────────────────

  /// Notifica que um pedido foi integrado ao ERP com sucesso.
  ///
  /// [customerName]: nome do cliente para exibir no corpo da notificação.
  /// [erpOrderId]:   número gerado pelo ERP (ex: "12345").
  Future<void> notifyOrderSynced({
    required String orderId,
    required String customerName,
    required String erpOrderId,
  }) async {
    if (!_initialized || kIsWeb) return;

    await _plugin.show(
      orderId.hashCode,
      '✅ Pedido integrado ao ERP',
      '$customerName · ERP #$erpOrderId',
      _details(color: const Color(0xFF4CAF50)),
    );
  }

  /// Notifica que um pedido entrou em estado de erro de integração.
  ///
  /// [errorMessage]: mensagem de erro retornada pelo Worker.
  Future<void> notifyOrderError({
    required String orderId,
    required String customerName,
    required String errorMessage,
  }) async {
    if (!_initialized || kIsWeb) return;

    await _plugin.show(
      orderId.hashCode ^ 0xFF,
      '❌ Erro na integração do pedido',
      '$customerName: $errorMessage',
      _details(color: const Color(0xFFF44336)),
    );
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  NotificationDetails _details({required Color color}) {
    final android = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance:         Importance.high,
      priority:           Priority.high,
      color:              color,
      icon:               '@mipmap/ic_launcher',
    );

    const ios = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    return NotificationDetails(android: android, iOS: ios);
  }
}

/// Composição dos serviços do app, acessível na árvore de widgets via [Services.of].
library;

import 'package:flutter/widgets.dart';

import '../core/api/api_client.dart';
import '../core/config/app_config.dart';
import '../core/db/local_db.dart';
import '../core/device/device_identity.dart';
import '../core/session/session_controller.dart';
import '../core/sync/sync_service.dart';

class AppServices {
  AppServices._(this.config, this.db, this.api, this.device, this.session, this.sync);

  final AppConfig config;
  final LocalDb db;
  final ApiClient api;
  final DeviceIdentity device;
  final SessionController session;
  final SyncService sync;

  static Future<AppServices> create() async {
    final config = await AppConfig.load();
    final db = await LocalDb.open();
    final api = ApiClient(config);
    final device = DeviceIdentity();
    final session = SessionController(config, api, device)..restore();
    final sync = SyncService(db, api, config, session);
    await sync.start();
    return AppServices._(config, db, api, device, session, sync);
  }
}

class Services extends InheritedWidget {
  const Services({super.key, required this.services, required super.child});
  final AppServices services;

  static AppServices of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<Services>()!.services;

  @override
  bool updateShouldNotify(Services oldWidget) => false;
}

/// Modelos da API do Coliseu Estoque.
///
/// Conferência cega: o app NUNCA recebe a quantidade esperada. Só sabe quais produtos
/// o documento tem (se a empresa permitir) e o que o próprio operador já contou.
library;

double parseQty(Object? v) => v == null ? 0 : (v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0);

class UserInfo {
  final String id, name, login, role;
  const UserInfo({required this.id, required this.name, required this.login, required this.role});
  factory UserInfo.fromJson(Map<String, dynamic> j) =>
      UserInfo(id: j['id'], name: j['name'], login: j['login'], role: j['role']);
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'login': login, 'role': role};
  bool get isSupervisor => role == 'supervisor' || role == 'admin';
}

class TenantSettings {
  final bool allowManualQty;
  final bool showItemList;
  final int maxRecounts;
  const TenantSettings({this.allowManualQty = true, this.showItemList = true, this.maxRecounts = 1});
  factory TenantSettings.fromJson(Map<String, dynamic>? j) => TenantSettings(
        allowManualQty: j?['allowManualQty'] ?? true,
        showItemList: j?['showItemList'] ?? true,
        maxRecounts: j?['maxRecounts'] ?? 1,
      );
  Map<String, dynamic> toJson() =>
      {'allowManualQty': allowManualQty, 'showItemList': showItemList, 'maxRecounts': maxRecounts};
}

class Session {
  final String token;
  final UserInfo user;
  final String companyName;
  final TenantSettings settings;
  const Session({required this.token, required this.user, required this.companyName, required this.settings});

  factory Session.fromJson(Map<String, dynamic> j) => Session(
        token: j['token'],
        user: UserInfo.fromJson(j['user']),
        companyName: (j['company'] as Map?)?['name'] ?? '',
        settings: TenantSettings.fromJson(j['settings']),
      );
  Map<String, dynamic> toJson() => {
        'token': token,
        'user': user.toJson(),
        'company': {'name': companyName},
        'settings': settings.toJson(),
      };
}

class DocLock {
  final String userName;
  final bool mine;
  final DateTime? expiresAt;
  const DocLock({required this.userName, required this.mine, this.expiresAt});
  factory DocLock.fromJson(Map<String, dynamic> j) => DocLock(
        userName: j['userName'] ?? '',
        mine: j['mine'] == true,
        expiresAt: DateTime.tryParse(j['expiresAt'] ?? ''),
      );
}

class DocSummary {
  final String id, source, erpKey, status;
  final String? number, customerName, sellerName;
  final DateTime? issuedAt;
  final int round, priority;
  final int? itemCount;
  final DocLock? lock;

  const DocSummary({
    required this.id,
    required this.source,
    required this.erpKey,
    required this.status,
    this.number,
    this.customerName,
    this.sellerName,
    this.issuedAt,
    this.round = 0,
    this.priority = 0,
    this.itemCount,
    this.lock,
  });

  factory DocSummary.fromJson(Map<String, dynamic> j) => DocSummary(
        id: j['id'],
        source: j['source'],
        erpKey: j['erpKey'],
        status: j['status'],
        number: j['number'],
        customerName: j['customerName'],
        sellerName: j['sellerName'],
        issuedAt: DateTime.tryParse(j['issuedAt'] ?? '')?.toLocal(),
        round: j['round'] ?? 0,
        priority: j['priority'] ?? 0,
        itemCount: j['itemCount'],
        lock: j['lock'] == null ? null : DocLock.fromJson(j['lock']),
      );

  String get title => '${source == 'NFS' ? 'Nota' : 'Pedido'} ${number ?? erpKey}';
  bool get isCountable => status == 'AGUARDANDO' || status == 'EM_CONFERENCIA' || status == 'DIVERGENTE';
}

class BlindItem {
  final String productErpId, description;
  final String? unit;
  final bool mustRecount, isExtra;
  const BlindItem({required this.productErpId, required this.description, this.unit, this.mustRecount = false, this.isExtra = false});
  factory BlindItem.fromJson(Map<String, dynamic> j) => BlindItem(
        productErpId: j['productErpId'],
        description: j['description'] ?? '',
        unit: j['unit'],
        mustRecount: j['mustRecount'] == true,
        isExtra: j['isExtra'] == true,
      );
}

class UnknownScan {
  final String eventId, barcode;
  final double qty;
  const UnknownScan({required this.eventId, required this.barcode, required this.qty});
  factory UnknownScan.fromJson(Map<String, dynamic> j) =>
      UnknownScan(eventId: j['eventId'], barcode: j['barcode'] ?? '', qty: parseQty(j['qty']));
}

class DocDetail {
  final DocSummary header;
  final List<BlindItem> items;
  /// código de barras → (produto, fator da embalagem)
  final Map<String, ({String productErpId, double factor})> barcodes;
  /// produto → quantidade já contada NESTA rodada (confirmada pelo servidor)
  final Map<String, double> counts;
  final List<UnknownScan> unknownScans;
  final Set<String> recount;
  final TenantSettings settings;

  const DocDetail({
    required this.header,
    required this.items,
    required this.barcodes,
    required this.counts,
    required this.unknownScans,
    required this.recount,
    required this.settings,
  });

  factory DocDetail.fromJson(Map<String, dynamic> j) => DocDetail(
        header: DocSummary.fromJson(j),
        items: [for (final i in (j['items'] as List? ?? const [])) BlindItem.fromJson(i)],
        barcodes: {
          for (final b in (j['barcodes'] as List? ?? const []))
            b['barcode'] as String: (productErpId: b['productErpId'] as String, factor: parseQty(b['factor']))
        },
        counts: {for (final e in ((j['counts'] as Map?) ?? const {}).entries) e.key as String: parseQty(e.value)},
        unknownScans: [for (final u in (j['unknownScans'] as List? ?? const [])) UnknownScan.fromJson(u)],
        recount: {for (final r in (j['recount'] as List? ?? const [])) r as String},
        settings: TenantSettings.fromJson(j['settings']),
      );
}

/// Resultado do fechamento da rodada — sem quantidades esperadas.
class FinalizeResult {
  final String status;
  final int round;
  final List<({String productErpId, String description})> recount;
  const FinalizeResult({required this.status, required this.round, required this.recount});
  factory FinalizeResult.fromJson(Map<String, dynamic> j) => FinalizeResult(
        status: j['status'],
        round: j['round'] ?? 0,
        recount: [
          for (final r in (j['recount'] as List? ?? const []))
            (productErpId: r['productErpId'] as String, description: (r['description'] ?? '') as String)
        ],
      );
}

const statusLabels = {
  'AGUARDANDO': 'Aguardando',
  'EM_CONFERENCIA': 'Em conferência',
  'DIVERGENTE': 'Recontagem',
  'AGUARDANDO_APROVACAO': 'Com supervisor',
  'CONCLUIDO': 'Concluído',
  'CANCELADO': 'Cancelado',
};

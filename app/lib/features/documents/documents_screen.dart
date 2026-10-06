/// Fila de documentos para conferência — separada em Entradas (recebimento) e Saídas (expedição).
///
/// O leitor do coletor funciona direto nesta tela: bipar o DANFE, o número do pedido
/// ou da NF abre a conferência daquele documento.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/services.dart';
import '../../app/theme.dart';
import '../../core/api/api_client.dart';
import '../../core/scan/scanner_input.dart';
import '../../models/models.dart';
import '../conference/camera_scanner_sheet.dart';
import '../conference/conference_screen.dart';
import 'relogin_dialog.dart';

class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key});

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  static const _queueStatuses = 'AGUARDANDO,EM_CONFERENCIA,DIVERGENTE';

  String _flow = 'saida';
  List<DocSummary> _docs = [];
  final Map<String, int> _counts = {'entrada': 0, 'saida': 0};
  bool _loading = true;
  bool _fromCache = false;
  bool _mine = false;
  String _q = '';
  String? _error;
  Timer? _debounce;
  Timer? _autoRefresh;
  StreamSubscription? _notices;
  final _scanner = GlobalKey<ScannerInputState>();

  String get _cacheKey => '__lista_$_flow';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final s = Services.of(context);
      _notices = s.sync.notices.stream.listen((n) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(n.message)));
      });
      _load();
      // A fila muda o tempo todo (novos pedidos do ERP, notas importadas, colegas assumindo documentos).
      _autoRefresh = Timer.periodic(const Duration(seconds: 30), (_) => _load(silent: true));
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _autoRefresh?.cancel();
    _notices?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    final s = Services.of(context);
    if (!silent) setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        s.api.get('/v1/documents', query: {
          'flow': _flow,
          'status': _queueStatuses,
          if (_mine) 'mine': '1',
          if (_q.isNotEmpty) 'q': _q,
          'limit': 100,
        }),
        s.api.get('/v1/documents/counts', query: {'flow': 'entrada', 'days': 1}),
        s.api.get('/v1/documents/counts', query: {'flow': 'saida', 'days': 1}),
      ]);
      final items = (results[0]['items'] as List).cast<Map<String, dynamic>>();
      for (final (i, f) in [(1, 'entrada'), (2, 'saida')]) {
        final by = (results[i]['byStatus'] as Map?) ?? const {};
        _counts[f] = _queueStatuses.split(',').fold<int>(0, (sum, k) => sum + ((by[k] as num?)?.toInt() ?? 0));
      }
      if (!_mine && _q.isEmpty) await s.db.cacheDocument(_cacheKey, jsonEncode(items));
      if (mounted) setState(() { _docs = items.map(DocSummary.fromJson).toList(); _fromCache = false; _error = null; });
    } on ApiException catch (e) {
      if (e.isNetwork) {
        final cached = await s.db.cachedDocument(_cacheKey);
        if (cached != null && mounted) {
          setState(() {
            _docs = (jsonDecode(cached) as List).cast<Map<String, dynamic>>().map(DocSummary.fromJson).toList();
            _fromCache = true;
          });
        } else if (!silent && mounted) {
          setState(() => _error = e.message);
        }
      } else if (!silent && mounted) {
        setState(() => _error = e.message);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(DocSummary d) async {
    if (!d.isCountable) {
      _snack('${d.title} está "${statusLabel(d)}" — não há o que conferir.');
      return;
    }
    if (d.lock != null && !d.lock!.mine) {
      _snack('Em conferência por ${d.lock!.userName}.');
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ConferenceScreen(documentId: d.id, title: d.title, flow: d.flow)));
    if (mounted) _load(silent: true);
    _scanner.currentState?.refocus();
  }

  /// Código lido na fila: DANFE (44 dígitos), nº do pedido ou da NF.
  Future<void> _lookup(String code) async {
    final s = Services.of(context);
    try {
      final r = await s.api.get('/v1/documents/lookup', query: {'code': code});
      final items = [for (final i in (r['items'] as List? ?? const [])) DocSummary.fromJson(Map<String, dynamic>.from(i as Map))];
      if (!mounted) return;
      if (items.isEmpty) {
        final parsed = (r['parsed'] as Map?) ?? const {};
        final nfe = parsed['kind'] == 'nfe';
        _snack(nfe
            ? (parsed['valid'] == false
                ? 'Chave do DANFE inválida — leia de novo.'
                : 'NF ${parsed['number']} ainda não foi importada. Peça ao supervisor para importar o XML no painel.')
            : 'Nenhum documento com o código $code.');
        return;
      }
      final doc = items.length == 1 ? items.first : await _pick(items);
      if (doc != null) await _open(doc);
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }

  Future<DocSummary?> _pick(List<DocSummary> items) => showModalBottomSheet<DocSummary>(
        context: context,
        builder: (c) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Padding(padding: EdgeInsets.all(16), child: Text('Mais de um documento — escolha:', style: TextStyle(fontWeight: FontWeight.w700))),
            for (final d in items)
              ListTile(
                leading: _FlowBadge(flow: d.flow),
                title: Text(d.title),
                subtitle: Text(d.customerName ?? ''),
                trailing: Text(statusLabel(d)),
                onTap: () => Navigator.pop(c, d),
              ),
          ]),
        ),
      );

  Future<void> _camera() async {
    String? first;
    await showCameraScanner(context, (code) async {
      if (first != null) return;
      first = code;
      Navigator.of(context).pop();
    });
    if (first != null) await _lookup(first!);
    _scanner.currentState?.refocus();
  }

  Future<void> _logout() async {
    final s = Services.of(context);
    if (s.sync.pending.value > 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Há leituras não enviadas'),
          content: Text('${s.sync.pending.value} leitura(s) ainda estão no aparelho. Elas serão enviadas no próximo login. Sair mesmo assim?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Ficar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Sair')),
          ],
        ),
      );
      if (ok != true) return;
    }
    await s.session.logout();
  }

  void _snack(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _setFlow(String f) {
    if (f == _flow) return;
    setState(() { _flow = f; _docs = []; });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    final user = s.session.session!.user;
    final color = flowColor(_flow);
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Coliseu Estoque'),
          Text('${user.name} · ${s.session.companyName}', style: Theme.of(context).textTheme.bodySmall),
        ]),
        actions: [
          IconButton(tooltip: 'Atualizar', icon: const Icon(Icons.refresh), onPressed: _load),
          IconButton(tooltip: 'Sair', icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _camera,
        backgroundColor: color,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.qr_code_scanner),
        label: Text(_flow == 'entrada' ? 'Ler DANFE' : 'Ler pedido'),
      ),
      body: Column(children: [
        ScannerInput(key: _scanner, onCode: _lookup),
        _StatusBanners(onRelogin: () => showReloginDialog(context)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(children: [
            Expanded(child: _FlowTab(flow: 'entrada', count: _counts['entrada']!, selected: _flow == 'entrada', onTap: () => _setFlow('entrada'))),
            const SizedBox(width: 10),
            Expanded(child: _FlowTab(flow: 'saida', count: _counts['saida']!, selected: _flow == 'saida', onTap: () => _setFlow('saida'))),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Row(children: [
            Expanded(
              child: TextField(
                decoration: InputDecoration(
                    hintText: _flow == 'entrada' ? 'NF ou fornecedor' : 'Pedido ou cliente', prefixIcon: const Icon(Icons.search), isDense: true),
                onChanged: (v) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 350), () { _q = v.trim(); _load(); });
                },
              ),
            ),
            const SizedBox(width: 10),
            FilterChip(label: const Text('Minhas'), selected: _mine, onSelected: (v) { setState(() => _mine = v); _load(); }),
          ]),
        ),
        if (_fromCache)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text('Sem conexão — mostrando a última lista recebida.', style: TextStyle(color: AppColors.warn)),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: _loading && _docs.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _error != null && _docs.isEmpty
                    ? ListView(children: [Padding(padding: const EdgeInsets.all(32), child: Text(_error!, textAlign: TextAlign.center))])
                    : _docs.isEmpty
                        ? ListView(children: [_Empty(flow: _flow)])
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                            itemCount: _docs.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (_, i) => _DocCard(doc: _docs[i], onTap: () => _open(_docs[i])),
                          ),
          ),
        ),
      ]),
    );
  }
}

class _FlowTab extends StatelessWidget {
  const _FlowTab({required this.flow, required this.count, required this.selected, required this.onTap});
  final String flow;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = flowColor(flow);
    final entrada = flow == 'entrada';
    return Material(
      color: selected ? color : Theme.of(context).cardTheme.color,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: selected ? color : Theme.of(context).dividerColor)),
          child: Row(children: [
            Icon(entrada ? Icons.move_to_inbox_outlined : Icons.local_shipping_outlined, color: selected ? Colors.white : color),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(entrada ? 'Entradas' : 'Saídas', style: TextStyle(fontWeight: FontWeight.w800, color: selected ? Colors.white : null)),
                Text(entrada ? 'Recebimento' : 'Expedição', style: TextStyle(fontSize: 11.5, color: selected ? Colors.white70 : Theme.of(context).colorScheme.onSurfaceVariant)),
              ]),
            ),
            if (count > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: selected ? Colors.white : color.withValues(alpha: .14), borderRadius: BorderRadius.circular(99)),
                child: Text('$count', style: TextStyle(fontWeight: FontWeight.w800, color: color)),
              ),
          ]),
        ),
      ),
    );
  }
}

class _FlowBadge extends StatelessWidget {
  const _FlowBadge({required this.flow});
  final String flow;
  @override
  Widget build(BuildContext context) {
    final color = flowColor(flow);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(6)),
      child: Text(flow == 'entrada' ? 'ENTRADA' : 'SAÍDA', style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w800)),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.flow});
  final String flow;
  @override
  Widget build(BuildContext context) {
    final entrada = flow == 'entrada';
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(children: [
        Icon(entrada ? Icons.move_to_inbox_outlined : Icons.local_shipping_outlined, size: 56, color: flowColor(flow).withValues(alpha: .5)),
        const SizedBox(height: 12),
        Text(entrada ? 'Nenhuma nota para conferir.' : 'Nenhum pedido para separar. 🎉',
            textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 6),
        Text(
          entrada
              ? 'Quando a mercadoria chegar, o supervisor importa o XML no painel e a nota aparece aqui.'
              : 'Os pedidos de venda chegam do ERP automaticamente.',
          textAlign: TextAlign.center,
        ),
      ]),
    );
  }
}

class _DocCard extends StatelessWidget {
  const _DocCard({required this.doc, required this.onTap});
  final DocSummary doc;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = statusColor(doc.status);
    final lockedByOther = doc.lock != null && !doc.lock!.mine;
    final errors = doc.alerts.where((a) => a.isError).length;
    final progress = doc.productCount != null && doc.productCount! > 0
        ? ((doc.countedProducts ?? 0) / doc.productCount!).clamp(0.0, 1.0)
        : null;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: lockedByOther ? null : onTap,
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 5, color: color),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(doc.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
                    if (doc.priority > 0)
                      const Padding(padding: EdgeInsets.only(right: 6), child: Icon(Icons.priority_high, color: AppColors.danger, size: 20)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(99)),
                      child: Text(statusLabel(doc), style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 11.5)),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Text(doc.customerName ?? '—', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (doc.issuedAt != null) DateFormat('dd/MM HH:mm').format(doc.issuedAt!),
                      if (doc.itemCount != null) '${doc.itemCount} itens',
                      if (doc.isEntry && doc.orderNumber != null) 'PC ${doc.orderNumber}',
                      if (doc.lock != null) (doc.lock!.mine ? '🔒 com você' : '🔒 ${doc.lock!.userName}'),
                    ].join(' · '),
                    style: theme.textTheme.bodySmall,
                  ),
                  if (progress != null && doc.status != 'AGUARDANDO') ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(value: progress, minHeight: 6, color: color, backgroundColor: color.withValues(alpha: .12)),
                    ),
                  ],
                  if (doc.alerts.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(children: [
                      Icon(errors > 0 ? Icons.error_outline : Icons.warning_amber_rounded, size: 16, color: errors > 0 ? AppColors.danger : AppColors.warn),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          doc.alerts.first.message + (doc.alerts.length > 1 ? '  (+${doc.alerts.length - 1})' : ''),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: errors > 0 ? AppColors.danger : AppColors.warn),
                        ),
                      ),
                    ]),
                  ],
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Avisos de conexão, fila pendente e sessão expirada.
class _StatusBanners extends StatelessWidget {
  const _StatusBanners({required this.onRelogin});
  final VoidCallback onRelogin;

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([s.sync.online, s.sync.pending, s.session]),
      builder: (context, _) {
        final banners = <Widget>[];
        if (s.session.sessionExpired || (s.session.offline && s.sync.online.value)) {
          banners.add(_banner(context, AppColors.warn, Icons.lock_clock,
              s.session.sessionExpired ? 'Sessão expirada. Entre de novo para enviar as leituras.' : 'Conexão voltou. Confirme seu PIN para enviar as leituras.',
              action: TextButton(onPressed: onRelogin, child: const Text('Entrar'))));
        }
        if (!s.sync.online.value) {
          banners.add(_banner(context, Colors.grey.shade700, Icons.cloud_off, 'Sem conexão — você pode continuar conferindo.'));
        }
        if (s.sync.pending.value > 0) {
          banners.add(_banner(context, AppColors.brand, Icons.cloud_upload_outlined,
              '${s.sync.pending.value} leitura(s) aguardando envio',
              action: TextButton(onPressed: s.sync.flushAll, child: const Text('Enviar'))));
        }
        return Column(children: banners);
      },
    );
  }

  Widget _banner(BuildContext context, Color color, IconData icon, String text, {Widget? action}) => Container(
        width: double.infinity,
        color: color.withValues(alpha: .12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600))),
          if (action != null) action,
        ]),
      );
}

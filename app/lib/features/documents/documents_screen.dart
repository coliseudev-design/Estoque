/// Fila de documentos para conferência.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/services.dart';
import '../../app/theme.dart';
import '../../core/api/api_client.dart';
import '../../models/models.dart';
import '../conference/conference_screen.dart';
import 'relogin_dialog.dart';

class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key});

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  static const _queueStatuses = 'AGUARDANDO,EM_CONFERENCIA,DIVERGENTE';
  static const _listCacheKey = '__lista__';

  List<DocSummary> _docs = [];
  bool _loading = true;
  bool _fromCache = false;
  bool _mine = false;
  String _q = '';
  String? _error;
  Timer? _debounce;
  Timer? _autoRefresh;
  StreamSubscription? _notices;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final s = Services.of(context);
      _notices = s.sync.notices.stream.listen((n) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(n.message)));
      });
      _load();
      // A fila muda o tempo todo (novos pedidos do ERP, colegas assumindo documentos).
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
      final res = await s.api.get('/v1/documents', query: {
        'status': _queueStatuses,
        if (_mine) 'mine': '1',
        if (_q.isNotEmpty) 'q': _q,
        'limit': 100,
      });
      final items = (res['items'] as List).cast<Map<String, dynamic>>();
      if (!_mine && _q.isEmpty) await s.db.cacheDocument(_listCacheKey, jsonEncode(items));
      setState(() { _docs = items.map(DocSummary.fromJson).toList(); _fromCache = false; _error = null; });
    } on ApiException catch (e) {
      if (e.isNetwork) {
        final cached = await s.db.cachedDocument(_listCacheKey);
        if (cached != null) {
          setState(() {
            _docs = (jsonDecode(cached) as List).cast<Map<String, dynamic>>().map(DocSummary.fromJson).toList();
            _fromCache = true;
          });
        } else if (!silent) {
          setState(() => _error = e.message);
        }
      } else if (!silent) {
        setState(() => _error = e.message);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(DocSummary d) async {
    if (!d.isCountable) return;
    if (d.lock != null && !d.lock!.mine) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Em conferência por ${d.lock!.userName}.')));
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ConferenceScreen(documentId: d.id, title: d.title)));
    if (mounted) _load(silent: true);
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

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    final user = s.session.session!.user;
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Conferência'),
          Text('${user.name} · ${s.session.companyName}', style: Theme.of(context).textTheme.bodySmall),
        ]),
        actions: [
          IconButton(tooltip: 'Atualizar', icon: const Icon(Icons.refresh), onPressed: _load),
          IconButton(tooltip: 'Sair', icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      body: Column(children: [
        _StatusBanners(onRelogin: () => showReloginDialog(context)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(children: [
            Expanded(
              child: TextField(
                decoration: const InputDecoration(
                    hintText: 'Nº da nota ou cliente', prefixIcon: Icon(Icons.search), isDense: true),
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
                        ? ListView(children: const [Padding(padding: EdgeInsets.all(48), child: Text('Nenhum documento na fila. 🎉', textAlign: TextAlign.center))])
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
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

class _DocCard extends StatelessWidget {
  const _DocCard({required this.doc, required this.onTap});
  final DocSummary doc;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = statusColor(doc.status);
    final lockedByOther = doc.lock != null && !doc.lock!.mine;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: lockedByOther ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(width: 4, height: 54, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(doc.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                  if (doc.priority > 0) const Padding(padding: EdgeInsets.only(right: 6), child: Icon(Icons.priority_high, color: AppColors.danger, size: 20)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(6)),
                    child: Text(statusLabels[doc.status] ?? doc.status, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
                  ),
                ]),
                const SizedBox(height: 4),
                Text(doc.customerName ?? '—', maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  [
                    if (doc.issuedAt != null) DateFormat('dd/MM HH:mm').format(doc.issuedAt!),
                    if (doc.itemCount != null) '${doc.itemCount} itens',
                    if (doc.lock != null) (doc.lock!.mine ? '🔒 com você' : '🔒 ${doc.lock!.userName}'),
                  ].join(' · '),
                  style: theme.textTheme.bodySmall,
                ),
              ]),
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

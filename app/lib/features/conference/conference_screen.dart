/// Tela de conferência cega.
///
/// O operador bipa (coletor ou câmera) ou digita; vê o que ELE contou, nunca o esperado.
/// Ao finalizar, a API compara e devolve: concluído, recontar (com a lista) ou supervisor.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/services.dart';
import '../../app/theme.dart';
import '../../core/api/api_client.dart';
import '../../core/scan/scanner_input.dart';
import '../../models/models.dart';
import '../documents/relogin_dialog.dart';
import 'camera_scanner_sheet.dart';
import 'conference_controller.dart';

class ConferenceScreen extends StatefulWidget {
  const ConferenceScreen({super.key, required this.documentId, required this.title, this.flow = 'saida'});
  final String documentId;
  final String title;
  /// entrada = conferência da nota de compra; saida = separação do pedido.
  final String flow;

  @override
  State<ConferenceScreen> createState() => _ConferenceScreenState();
}

class _ConferenceScreenState extends State<ConferenceScreen> {
  late final ConferenceController _c;
  final _scanner = GlobalKey<ScannerInputState>();
  int _packs = 1;
  bool _finishing = false;

  // didChangeDependencies roda de novo ao girar a tela (MediaQuery muda):
  // o controller é criado uma única vez.
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final s = Services.of(context);
    _c = ConferenceController(widget.documentId, s.api, s.db, s.sync)..open();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _onCode(String code, String origin) async {
    if (_c.detail == null) return;
    final fb = await _c.scan(code, packs: _packs, origin: origin);
    if (fb.isError) {
      HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 120));
      HapticFeedback.heavyImpact();
    } else {
      HapticFeedback.lightImpact();
      SystemSound.play(SystemSoundType.click);
    }
    if (_packs != 1 && mounted) setState(() => _packs = 1);
  }

  Future<void> _manualEntry() async {
    final ctrl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Digitar código'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'EAN ou código do produto'),
          onSubmitted: (v) => Navigator.pop(c, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text), child: const Text('Contar')),
        ],
      ),
    );
    ctrl.dispose();
    if (code != null && code.trim().isNotEmpty) await _onCode(code, 'teclado');
    _scanner.currentState?.refocus();
  }

  Future<void> _camera() async {
    await showCameraScanner(context, (code) => _onCode(code, 'camera'));
    _scanner.currentState?.refocus();
  }

  Future<void> _undo(String eventId) async {
    try {
      await _c.undo(eventId);
    } on ApiException catch (e) {
      _snack(e.message);
    }
    _scanner.currentState?.refocus();
  }

  Future<void> _finalize() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Finalizar conferência?'),
        content: Text(_c.isRecount
            ? 'Confirma que recontou todos os produtos indicados?'
            : 'Confirma que contou todos os itens? O sistema vai comparar com o documento.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Continuar contando')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Finalizar')),
        ],
      ),
    );
    if (ok != true) {
      _scanner.currentState?.refocus();
      return;
    }

    setState(() => _finishing = true);
    try {
      final r = await _c.finalize();
      if (!mounted) return;
      await _showResult(r);
    } on ApiException catch (e) {
      if (e.code == 'UNKNOWN_BARCODES') {
        await _c.reload();
        _snack('Há códigos não reconhecidos. Desfaça essas leituras antes de finalizar.');
      } else if (e.code == 'LOCK_LOST' || e.code == 'INVALID_STATUS') {
        _snack(e.message);
        if (mounted) Navigator.pop(context);
      } else {
        _snack(e.message);
      }
    } finally {
      if (mounted) setState(() => _finishing = false);
      _scanner.currentState?.refocus();
    }
  }

  Future<void> _showResult(FinalizeResult r) async {
    switch (r.status) {
      case 'CONCLUIDO':
        SystemSound.play(SystemSoundType.click);
        await _resultDialog(Icons.check_circle, AppColors.ok, 'Conferência concluída', 'Tudo confere.');
        if (mounted) Navigator.pop(context);
      case 'DIVERGENTE':
        HapticFeedback.heavyImpact();
        await showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
            icon: const Icon(Icons.replay, color: AppColors.warn, size: 40),
            title: const Text('Recontagem necessária'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Há divergência. Reconte somente estes produtos:'),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView(shrinkWrap: true, children: [
                    for (final p in r.recount)
                      ListTile(dense: true, leading: const Icon(Icons.inventory_2_outlined), title: Text(p.description.isEmpty ? p.productErpId : p.description), subtitle: Text(p.productErpId)),
                  ]),
                ),
              ]),
            ),
            actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Começar recontagem'))],
          ),
        );
      default:
        await _resultDialog(Icons.supervisor_account, AppColors.danger, 'Enviado ao supervisor',
            'A divergência continuou após a recontagem. O supervisor vai analisar.');
        if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _resultDialog(IconData icon, Color color, String title, String body) => showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          icon: Icon(icon, color: color, size: 48),
          title: Text(title),
          content: Text(body, textAlign: TextAlign.center),
          actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Próximo documento'))],
        ),
      );

  Future<void> _release() async {
    try {
      await _c.release();
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }

  void _snack(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([_c, s.session]),
      builder: (context, _) {
        final d = _c.detail;
        return Scaffold(
          appBar: AppBar(
            title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.title),
              if (d?.header.customerName != null)
                Text(d!.header.customerName!, style: Theme.of(context).textTheme.bodySmall, overflow: TextOverflow.ellipsis),
            ]),
            actions: [
              PopupMenuButton<String>(
                onSelected: (v) => v == 'release' ? _release() : null,
                itemBuilder: (_) => const [PopupMenuItem(value: 'release', child: Text('Liberar documento para outro operador'))],
              ),
            ],
          ),
          body: _c.loading
              ? const Center(child: CircularProgressIndicator())
              : _c.error != null
                  ? Center(child: Padding(padding: const EdgeInsets.all(32), child: Text(_c.error!, textAlign: TextAlign.center)))
                  : _body(context, d!),
          bottomNavigationBar: d == null || _c.error != null ? null : _bottomBar(context, d),
        );
      },
    );
  }

  Widget _body(BuildContext context, DocDetail d) {
    final s = Services.of(context);
    // Lista de conferência: produtos do documento (se a empresa mostra) + o que foi bipado.
    // Na recontagem, só os produtos a recontar. Nunca mostra a quantidade esperada.
    final current = _c.counts;
    final ids = <String>{
      ...current.keys,
      if (_c.isRecount) ...d.recount else ...d.items.where((i) => !i.isExtra).map((i) => i.productErpId),
    };
    final counts = [for (final id in ids) MapEntry(id, current[id] ?? 0.0)]
      ..sort((a, b) {
        final ra = d.recount.contains(a.key) ? 0 : 1, rb = d.recount.contains(b.key) ? 0 : 1;
        if (ra != rb) return ra - rb;
        final da = a.value > 0 ? 1 : 0, db = b.value > 0 ? 1 : 0;
        if (da != db) return da - db; // pendentes primeiro
        return _c.nameOf(a.key).compareTo(_c.nameOf(b.key));
      });
    final scope = _c.isRecount ? d.recount : d.items.where((i) => !i.isExtra).map((i) => i.productErpId).toSet();
    final done = scope.where((p) => (current[p] ?? 0) > 0).length;
    final entrada = widget.flow == 'entrada';
    final fColor = flowColor(widget.flow);

    return Column(children: [
      ScannerInput(key: _scanner, onCode: (code) => _onCode(code, 'coletor')),
      if (s.session.sessionExpired)
        _strip(AppColors.warn, Icons.lock_clock, 'Sessão expirada — as leituras estão salvas.', action: TextButton(onPressed: () => showReloginDialog(context), child: const Text('Entrar'))),
      if (_c.offlineMode)
        _strip(Colors.grey.shade700, Icons.cloud_off, 'Offline — leituras salvas no aparelho e enviadas quando a conexão voltar.'),
      if (_c.isRecount)
        _strip(AppColors.warn, Icons.replay, 'Recontagem (rodada ${_c.round + 1}): reconte os ${d.recount.length} produto(s) destacados.')
      else
        _strip(fColor, entrada ? Icons.move_to_inbox_outlined : Icons.local_shipping_outlined,
            entrada ? 'Recebimento: bipe cada volume. Caixa com código próprio soma a caixa inteira.' : 'Separação: pegue cada item e bipe. Conte o que separou.'),
      if (scope.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Row(children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(value: done / scope.length, minHeight: 8, color: fColor, backgroundColor: fColor.withValues(alpha: .12)),
              ),
            ),
            const SizedBox(width: 10),
            Text('$done/${scope.length} ${_c.isRecount ? 'recontados' : 'produtos'}', style: const TextStyle(fontWeight: FontWeight.w700)),
          ]),
        ),
      Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: _feedbackCard(context)),
      if (d.settings.allowManualQty) _packsRow(context),
      Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => _scanner.currentState?.refocus(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: [
              if (d.unknownScans.isNotEmpty) ...[
                Text('Códigos não reconhecidos', style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w700)),
                for (final u in d.unknownScans)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.error_outline, color: AppColors.danger),
                    title: Text(u.barcode),
                    trailing: TextButton(onPressed: () => _undo(u.eventId), child: const Text('Desfazer')),
                  ),
                const Divider(),
              ],
              Text(d.items.isEmpty ? 'Contado nesta rodada' : (entrada ? 'Itens da nota' : 'Lista de separação'),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              if (counts.isEmpty)
                const Padding(padding: EdgeInsets.all(24), child: Text('Bipe o primeiro item.', textAlign: TextAlign.center)),
              for (final e in counts)
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  decoration: BoxDecoration(
                    color: d.recount.contains(e.key) ? AppColors.warn.withValues(alpha: .10) : null,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListTile(
                    dense: true,
                    leading: Icon(e.value > 0 ? Icons.check_circle : Icons.radio_button_unchecked,
                        color: e.value > 0 ? AppColors.ok : Theme.of(context).disabledColor),
                    title: Text(_c.nameOf(e.key), maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text(e.key.replaceFirst('NFE:', 'cód. fornecedor ')),
                    trailing: Text(e.value > 0 ? _fmt(e.value) : '—', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                  ),
                ),
              if (_c.history.isNotEmpty) ...[
                const Divider(height: 28),
                Text('Últimas leituras', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                for (final h in _c.history.take(10))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(h.isError ? Icons.error_outline : Icons.check, color: h.isError ? AppColors.danger : AppColors.ok),
                    title: Text(h.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(h.code),
                    trailing: TextButton(onPressed: () => _undo(h.eventId), child: const Text('Desfazer')),
                  ),
              ],
            ],
          ),
        ),
      ),
    ]);
  }

  Widget _feedbackCard(BuildContext context) {
    final fb = _c.last;
    final color = fb == null ? Theme.of(context).colorScheme.surfaceContainerHighest : (fb.isError ? AppColors.danger : AppColors.ok);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: fb == null ? color : color.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: fb == null ? Colors.transparent : color, width: 2),
      ),
      child: fb == null
          ? const Text('Aguardando leitura… use o gatilho do coletor ou a câmera.', style: TextStyle(fontSize: 16))
          : Row(children: [
              Icon(fb.isError ? Icons.error : Icons.check_circle, color: color, size: 36),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(fb.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700), maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(fb.detail),
                ]),
              ),
              TextButton(onPressed: () => _undo(fb.eventId), child: const Text('Desfazer')),
            ]),
    );
  }

  Widget _packsRow(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Row(children: [
          const Expanded(child: Text('Quantidade na próxima leitura')),
          IconButton.outlined(onPressed: _packs > 1 ? () => setState(() => _packs--) : null, icon: const Icon(Icons.remove)),
          GestureDetector(
            onTap: () async {
              final ctrl = TextEditingController(text: '$_packs');
              final v = await showDialog<int>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Quantidade'),
                  content: TextField(controller: ctrl, autofocus: true, keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onSubmitted: (t) => Navigator.pop(c, int.tryParse(t))),
                  actions: [FilledButton(onPressed: () => Navigator.pop(c, int.tryParse(ctrl.text)), child: const Text('OK'))],
                ),
              );
              ctrl.dispose();
              if (v != null && v > 0) setState(() => _packs = v.clamp(1, 99999));
              _scanner.currentState?.refocus();
            },
            child: SizedBox(width: 64, child: Text('$_packs', textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700))),
          ),
          IconButton.outlined(onPressed: () => setState(() => _packs++), icon: const Icon(Icons.add)),
        ]),
      );

  Widget _bottomBar(BuildContext context, DocDetail d) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(children: [
            IconButton.filledTonal(iconSize: 28, tooltip: 'Câmera', onPressed: _camera, icon: const Icon(Icons.photo_camera_outlined)),
            const SizedBox(width: 8),
            IconButton.filledTonal(iconSize: 28, tooltip: 'Digitar código', onPressed: _manualEntry, icon: const Icon(Icons.keyboard_outlined)),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: _finishing ? null : _finalize,
                icon: _finishing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.done_all),
                label: Text(_c.isRecount ? 'Finalizar recontagem' : 'Finalizar'),
              ),
            ),
          ]),
        ),
      );

  Widget _strip(Color color, IconData icon, String text, {Widget? action}) => Container(
        width: double.infinity,
        color: color.withValues(alpha: .12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600))),
          if (action != null) action,
        ]),
      );

  static String _fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(3).replaceAll(RegExp(r'0+$'), '');
}

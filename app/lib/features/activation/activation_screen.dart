/// Conexão do aparelho com o Coliseu Estoque (uma vez por aparelho).
///
/// Três caminhos:
///   1. Ler o QR Code gerado no painel web (Cadastros → Aparelhos → Conectar aparelho)
///   2. Digitar o endereço da API + o código mostrado no painel (coletor sem câmera)
///   3. Chave de ativação do painel de licenças (Coliseu.Identity) — em "Avançado"
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../app/services.dart';
import '../../app/theme.dart';
import '../../core/api/api_client.dart';
import '../../core/session/session_controller.dart';

class ActivationScreen extends StatefulWidget {
  const ActivationScreen({super.key});

  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

enum _Mode { choose, manual, license }

class _ActivationScreenState extends State<ActivationScreen> {
  _Mode _mode = _Mode.choose;
  final _url = TextEditingController();
  final _code = TextEditingController();
  final _key = TextEditingController();
  final _identity = TextEditingController();
  final _apiOverride = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _ok;
  bool _init = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    final cfg = Services.of(context).config;
    _identity.text = cfg.identityUrl;
    _url.text = cfg.apiUrl;
    _apiOverride.text = cfg.apiUrl;
  }

  @override
  void dispose() {
    for (final c in [_url, _code, _key, _identity, _apiOverride]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() { _busy = true; _error = null; _ok = null; });
    try {
      await action();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scanQr() async {
    final raw = await Navigator.of(context).push<String>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => const _QrPage()),
    );
    if (raw == null || !mounted) return;
    final p = SessionController.parsePairingQr(raw);
    if (p == null) {
      setState(() => _error = 'Esse QR Code não é de pareamento do Coliseu Estoque. Gere um no painel: Cadastros → Aparelhos → Conectar aparelho.');
      return;
    }
    _url.text = p.apiUrl;
    _code.text = p.code;
    await _run(() => Services.of(context).session.pairDevice(apiUrl: p.apiUrl, code: p.code));
  }

  Future<void> _testConnection() => _run(() async {
        final url = SessionController.normalizeUrl(_url.text);
        if (url.isEmpty) throw const ApiException('Informe o endereço da API.');
        await Services.of(context).api.health(url);
        if (mounted) setState(() => _ok = 'Conexão OK com $url');
      });

  Future<void> _pairManual() => _run(() async {
        if (_url.text.trim().isEmpty || _code.text.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').length < 8) {
          throw const ApiException('Informe o endereço e o código de 8 caracteres mostrado no painel.');
        }
        await Services.of(context).session.pairDevice(apiUrl: _url.text, code: _code.text);
      });

  Future<void> _activateLicense() => _run(() async {
        if (_key.text.trim().length < 6) throw const ApiException('Informe a chave de ativação.');
        await Services.of(context).session.activate(
              identityUrl: _identity.text,
              activationKey: _key.text,
              apiUrlOverride: _apiOverride.text,
            );
      });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const _Brand(),
                const SizedBox(height: 18),
                const _Steps(current: 0),
                const SizedBox(height: 20),
                if (_mode == _Mode.choose) ..._choose(theme),
                if (_mode == _Mode.manual) ..._manual(theme),
                if (_mode == _Mode.license) ..._license(theme),
                if (_ok != null) _msg(theme, _ok!, AppColors.ok, Icons.check_circle),
                if (_error != null) _msg(theme, _error!, AppColors.danger, Icons.error_outline),
                if (_busy) const Padding(padding: EdgeInsets.only(top: 16), child: Center(child: CircularProgressIndicator())),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _choose(ThemeData theme) => [
        Text('Conecte este aparelho', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text('No computador, abra o painel do Coliseu Estoque → Cadastros → Aparelhos → Conectar aparelho. Vai aparecer um QR Code.',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 18),
        _Option(
          icon: Icons.qr_code_scanner,
          color: AppColors.brand,
          title: 'Ler QR do painel',
          subtitle: 'Aponte a câmera para o QR Code. É o jeito mais rápido.',
          onTap: _busy ? null : _scanQr,
          primary: true,
        ),
        const SizedBox(height: 10),
        _Option(
          icon: Icons.keyboard_alt_outlined,
          color: AppColors.entrada,
          title: 'Digitar endereço e código',
          subtitle: 'Para coletores sem câmera: o painel mostra os dois abaixo do QR.',
          onTap: _busy ? null : () => setState(() { _mode = _Mode.manual; _error = null; }),
        ),
        const SizedBox(height: 10),
        TextButton.icon(
          onPressed: _busy ? null : () => setState(() { _mode = _Mode.license; _error = null; }),
          icon: const Icon(Icons.key_outlined, size: 18),
          label: const Text('Tenho uma chave de ativação do painel de licenças'),
        ),
      ];

  List<Widget> _manual(ThemeData theme) => [
        _back(),
        Text('Digite o que aparece no painel', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        TextField(
          controller: _url,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Endereço da API',
            hintText: 'https://estoque.suaempresa.com.br',
            prefixIcon: Icon(Icons.dns_outlined),
            helperText: 'Na rede local: http://IP-do-computador:3100',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _code,
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          style: const TextStyle(fontSize: 22, letterSpacing: 3, fontWeight: FontWeight.w700),
          inputFormatters: [_PairCodeFormatter()],
          decoration: const InputDecoration(labelText: 'Código de pareamento', hintText: 'XXXX-XXXX', prefixIcon: Icon(Icons.pin_outlined)),
          onSubmitted: (_) => _pairManual(),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: OutlinedButton.icon(onPressed: _busy ? null : _testConnection, icon: const Icon(Icons.wifi_tethering), label: const Text('Testar'))),
          const SizedBox(width: 10),
          Expanded(flex: 2, child: FilledButton.icon(onPressed: _busy ? null : _pairManual, icon: const Icon(Icons.link), label: const Text('Conectar'))),
        ]),
      ];

  List<Widget> _license(ThemeData theme) => [
        _back(),
        Text('Chave de ativação', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text('Gerada no painel de licenças (módulo Estoque → Dispositivos). Conta no limite de aparelhos da licença.',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 16),
        TextField(
          controller: _key,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'Chave de ativação', prefixIcon: Icon(Icons.key_outlined)),
        ),
        const SizedBox(height: 12),
        TextField(controller: _identity, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Servidor de licenças')),
        const SizedBox(height: 12),
        TextField(
          controller: _apiOverride,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(labelText: 'URL da API do Estoque', helperText: 'Vazio = usa a URL cadastrada no módulo Estoque do painel'),
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: _busy ? null : _activateLicense, child: const Text('Ativar aparelho')),
      ];

  Widget _back() => Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _busy ? null : () => setState(() { _mode = _Mode.choose; _error = null; _ok = null; }),
          icon: const Icon(Icons.arrow_back, size: 18),
          label: const Text('Voltar'),
        ),
      );

  Widget _msg(ThemeData theme, String text, Color color, IconData icon) => Container(
        margin: const EdgeInsets.only(top: 16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: color.withValues(alpha: .10), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withValues(alpha: .35))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600))),
        ]),
      );
}

/// Formata o código como XXXX-XXXX enquanto digita.
class _PairCodeFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final raw = newValue.text.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final clipped = raw.length > 8 ? raw.substring(0, 8) : raw;
    final text = clipped.length > 4 ? '${clipped.substring(0, 4)}-${clipped.substring(4)}' : clipped;
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

class _Brand extends StatelessWidget {
  const _Brand();
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(children: [
      Container(
        width: 52, height: 52,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: const LinearGradient(colors: [AppColors.brand, AppColors.brand2]),
        ),
        child: const Icon(Icons.inventory_2_outlined, color: Colors.white, size: 28),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Coliseu Estoque', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
          Text('Conferência cega de entradas e saídas', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ]),
      ),
    ]);
  }
}

/// 1. Conectar aparelho → 2. Entrar com usuário + PIN → 3. Conferir.
class _Steps extends StatelessWidget {
  const _Steps({required this.current});
  final int current;
  @override
  Widget build(BuildContext context) {
    const labels = ['Conectar', 'Entrar', 'Conferir'];
    return Row(children: [
      for (var i = 0; i < labels.length; i++) ...[
        if (i > 0) Expanded(child: Container(height: 2, color: i <= current ? AppColors.brand : Theme.of(context).dividerColor)),
        Column(mainAxisSize: MainAxisSize.min, children: [
          CircleAvatar(
            radius: 13,
            backgroundColor: i < current ? AppColors.ok : i == current ? AppColors.brand : Theme.of(context).dividerColor,
            child: i < current
                ? const Icon(Icons.check, size: 15, color: Colors.white)
                : Text('${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 4),
          Text(labels[i], style: TextStyle(fontSize: 11.5, fontWeight: i == current ? FontWeight.w800 : FontWeight.w500)),
        ]),
      ],
    ]);
  }
}

class _Option extends StatelessWidget {
  const _Option({required this.icon, required this.color, required this.title, required this.subtitle, this.onTap, this.primary = false});
  final IconData icon;
  final Color color;
  final String title, subtitle;
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: primary ? color : theme.cardTheme.color,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: primary ? null : Border.all(color: theme.dividerColor),
          ),
          child: Row(children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(color: primary ? Colors.white24 : color.withValues(alpha: .12), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: primary ? Colors.white : color, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, color: primary ? Colors.white : null)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(fontSize: 13, color: primary ? Colors.white70 : theme.colorScheme.onSurfaceVariant)),
              ]),
            ),
            Icon(Icons.chevron_right, color: primary ? Colors.white : theme.colorScheme.onSurfaceVariant),
          ]),
        ),
      ),
    );
  }
}

/// Câmera para o QR de pareamento (fecha na primeira leitura).
class _QrPage extends StatefulWidget {
  const _QrPage();
  @override
  State<_QrPage> createState() => _QrPageState();
}

class _QrPageState extends State<_QrPage> {
  final _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: const Text('Ler QR do painel')),
      body: Stack(children: [
        MobileScanner(
          controller: _controller,
          onDetect: (capture) {
            final v = capture.barcodes.firstOrNull?.rawValue;
            if (_done || v == null) return;
            _done = true;
            HapticFeedback.mediumImpact();
            Navigator.pop(context, v);
          },
        ),
        Center(
          child: Container(
            width: 250, height: 250,
            decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 3), borderRadius: BorderRadius.circular(20)),
          ),
        ),
        const Positioned(
          left: 24, right: 24, bottom: 40,
          child: Text('Aponte para o QR Code da tela Aparelhos do painel', textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}

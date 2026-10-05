/// Login do operador no início do turno: usuário + PIN.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/services.dart';
import '../../core/api/api_client.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _login = TextEditingController();
  final _pin = TextEditingController();
  final _pinFocus = FocusNode();
  bool _busy = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_login.text.isEmpty) _login.text = Services.of(context).session.lastLogin;
  }

  @override
  void dispose() {
    _login.dispose();
    _pin.dispose();
    _pinFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_login.text.trim().isEmpty || _pin.text.length < 4) {
      setState(() => _error = 'Informe usuário e PIN.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    final services = Services.of(context);
    try {
      await services.session.login(_login.text, _pin.text);
      // Primeiro acesso do turno: atualiza o catálogo offline em segundo plano.
      services.sync.syncCatalog().catchError((_) {});
      services.sync.flushAll();
    } on ApiException catch (e) {
      _pin.clear();
      setState(() => _error = e.message);
      _pinFocus.requestFocus();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deactivate() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Desvincular aparelho?'),
        content: const Text('Será preciso uma nova chave de ativação do painel para usar este aparelho de novo.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Desvincular')),
        ],
      ),
    );
    if (ok == true && mounted) await Services.of(context).session.deactivate();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = Services.of(context).session;
    return Scaffold(
      appBar: AppBar(actions: [
        PopupMenuButton<String>(
          onSelected: (_) => _deactivate(),
          itemBuilder: (_) => const [PopupMenuItem(value: 'unlink', child: Text('Desvincular aparelho'))],
        ),
      ]),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(session.companyName, textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('Entre para iniciar o turno', textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 28),
                TextField(
                  controller: _login,
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: 'Usuário', prefixIcon: Icon(Icons.person_outline)),
                  onSubmitted: (_) => _pinFocus.requestFocus(),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _pin,
                  focusNode: _pinFocus,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
                  decoration: const InputDecoration(labelText: 'PIN', prefixIcon: Icon(Icons.lock_outline)),
                  onSubmitted: (_) => _submit(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : const Text('Entrar'),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

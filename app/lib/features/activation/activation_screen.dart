/// Ativação do aparelho no Coliseu.Identity (uma vez por aparelho).
library;

import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../core/api/api_client.dart';
import '../../core/config/app_config.dart';

class ActivationScreen extends StatefulWidget {
  const ActivationScreen({super.key});

  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<ActivationScreen> {
  final _form = GlobalKey<FormState>();
  final _key = TextEditingController();
  final _identity = TextEditingController(text: AppConfig.defaultIdentityUrl);
  final _api = TextEditingController();
  bool _advanced = false;
  bool _busy = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final cfg = Services.of(context).config;
    _identity.text = cfg.identityUrl;
    _api.text = cfg.apiUrl;
  }

  Future<void> _activate() async {
    if (!_form.currentState!.validate()) return;
    setState(() { _busy = true; _error = null; });
    try {
      await Services.of(context).session.activate(
            identityUrl: _identity.text,
            activationKey: _key.text,
            apiUrlOverride: _api.text,
          );
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _form,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Icon(Icons.inventory_2_outlined, size: 56, color: theme.colorScheme.primary),
                  const SizedBox(height: 16),
                  Text('Coliseu Estoque', textAlign: TextAlign.center, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text('Ative este aparelho com a chave gerada no painel de licenças (aba Dispositivos).',
                      textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 28),
                  TextFormField(
                    controller: _key,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: 'Chave de ativação', prefixIcon: Icon(Icons.key_outlined)),
                    validator: (v) => (v == null || v.trim().length < 6) ? 'Informe a chave de ativação' : null,
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: () => setState(() => _advanced = !_advanced),
                    icon: Icon(_advanced ? Icons.expand_less : Icons.expand_more),
                    label: const Text('Avançado'),
                  ),
                  if (_advanced) ...[
                    TextFormField(controller: _identity, keyboardType: TextInputType.url,
                        decoration: const InputDecoration(labelText: 'Servidor de licenças')),
                    const SizedBox(height: 12),
                    TextFormField(controller: _api, keyboardType: TextInputType.url,
                        decoration: const InputDecoration(
                            labelText: 'URL da API do Estoque',
                            helperText: 'Vazio = usa a URL cadastrada no módulo Estoque do painel')),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : _activate,
                    child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : const Text('Ativar aparelho'),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

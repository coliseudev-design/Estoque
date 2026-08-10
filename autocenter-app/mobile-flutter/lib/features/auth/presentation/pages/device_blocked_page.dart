import 'package:flutter/material.dart';

class DeviceBlockedPage extends StatelessWidget {
  final String? reason;
  final VoidCallback? onReactivate;

  const DeviceBlockedPage({
    super.key,
    this.reason,
    this.onReactivate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;

    return Scaffold(
      backgroundColor: isLight ? const Color(0xFFF5F7FF) : const Color(0xFF0D1117),
      appBar: AppBar(
        title: const Text('Dispositivo Bloqueado'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        foregroundColor: isLight ? Colors.black87 : Colors.white,
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.block_flipped, size: 80, color: Colors.red),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    'Acesso Revogado',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isLight ? const Color(0xFF1A1A2E) : Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    reason ?? 'Sua licença para este dispositivo foi revogada ou o módulo foi desabilitado.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: isLight ? const Color(0xFF64748B) : const Color(0xFF8B9AB1),
                    ),
                  ),
                  const SizedBox(height: 48),
                  if (onReactivate != null)
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: onReactivate,
                        icon: const Icon(Icons.vpn_key_rounded),
                        label: const Text(
                          'Inserir Nova Chave',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1C6EF2),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

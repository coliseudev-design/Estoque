import 'package:flutter/material.dart';

class DeviceBlockedScreen extends StatelessWidget {
  final String? reason;
  final VoidCallback? onReactivate;

  const DeviceBlockedScreen({
    super.key,
    this.reason,
    this.onReactivate,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dispositivo Bloqueado'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.block, size: 80, color: Colors.red),
                const SizedBox(height: 24),
                const Text(
                  'Acesso Revogado',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Text(
                  reason ?? 'Sua licença para este dispositivo foi revogada.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 32),
                if (onReactivate != null)
                  ElevatedButton.icon(
                    onPressed: onReactivate,
                    icon: const Icon(Icons.key),
                    label: const Text('Inserir Novo Código de Ativação'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

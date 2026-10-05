/// Revalida o operador (sessão expirada ou login feito offline) sem perder a fila.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/services.dart';
import '../../core/api/api_client.dart';

Future<void> showReloginDialog(BuildContext context) async {
  final s = Services.of(context);
  final login = s.session.session?.user.login ?? s.session.lastLogin;
  final pin = TextEditingController();
  String? error;
  bool busy = false;

  await showDialog<void>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) {
        Future<void> submit() async {
          setState(() { busy = true; error = null; });
          try {
            await s.session.login(login, pin.text);
            if (s.session.offline) {
              setState(() { error = 'Ainda sem conexão com o servidor.'; busy = false; });
              return;
            }
            await s.sync.flushAll();
            if (c.mounted) Navigator.pop(c);
          } on ApiException catch (e) {
            setState(() { error = e.message; busy = false; });
          }
        }

        return AlertDialog(
          title: Text('Confirme o PIN de $login'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: pin,
              autofocus: true,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
              decoration: const InputDecoration(labelText: 'PIN'),
              onSubmitted: (_) => submit(),
            ),
            if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, style: TextStyle(color: Theme.of(c).colorScheme.error))),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Depois')),
            FilledButton(onPressed: busy ? null : submit, child: const Text('Entrar')),
          ],
        );
      },
    ),
  );
  pin.dispose();
}

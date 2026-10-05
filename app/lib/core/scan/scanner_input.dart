/// Entrada do leitor físico (Zebra, Honeywell, Datalogic, leitor Bluetooth).
///
/// Esses leitores trabalham como TECLADO ("keyboard wedge"/DataWedge): digitam o
/// código e um Enter (ou Tab). Um campo invisível com foco permanente recebe essas
/// teclas sem abrir o teclado virtual (TextInputType.none).
///
/// Configuração recomendada no coletor:
///   Zebra DataWedge  → Keystroke output ON, "Send ENTER key" após os dados
///   Honeywell        → Data Processing Settings → Suffix = Enter (\r)
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ScannerInput extends StatefulWidget {
  const ScannerInput({super.key, required this.onCode, this.enabled = true});

  final ValueChanged<String> onCode;
  final bool enabled;

  @override
  State<ScannerInput> createState() => ScannerInputState();
}

class ScannerInputState extends State<ScannerInput> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode(debugLabel: 'scanner');

  /// Devolve o foco ao leitor (após fechar diálogos, câmera etc.).
  void refocus() {
    if (mounted && widget.enabled) _focus.requestFocus();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => refocus());
    _focus.addListener(() {
      // Foco perdido para "ninguém" (toque em área vazia): recupera. Se foi para outro
      // campo (quantidade, digitação manual), respeita — a tela devolve ao fechar.
      if (!_focus.hasFocus && widget.enabled) {
        Future.delayed(const Duration(milliseconds: 250), () {
          if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
          final current = FocusManager.instance.primaryFocus;
          if (current == null || current.context == null || current == FocusManager.instance.rootScope) refocus();
        });
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _emit(String raw) {
    final code = raw.replaceAll(RegExp(r'[\r\n\t]'), '').trim();
    _ctrl.clear();
    if (code.isNotEmpty) widget.onCode(code);
    refocus();
  }

  @override
  Widget build(BuildContext context) {
    // 1x1 e transparente: existe só para receber as teclas do leitor.
    return SizedBox(
      width: 1,
      height: 1,
      child: Opacity(
        opacity: 0,
        child: TextField(
          controller: _ctrl,
          focusNode: _focus,
          enabled: widget.enabled,
          autofocus: true,
          keyboardType: TextInputType.none,
          showCursor: false,
          enableSuggestions: false,
          autocorrect: false,
          inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'))],
          onSubmitted: _emit,
          onChanged: (v) {
            // Alguns leitores mandam Tab ou \n dentro do texto em vez de "submit".
            if (v.contains('\n') || v.contains('\t') || v.contains('\r')) _emit(v);
          },
        ),
      ),
    );
  }
}

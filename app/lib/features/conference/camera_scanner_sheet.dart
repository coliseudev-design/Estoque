/// Leitura contínua pela câmera — para celulares comuns, sem leitor físico.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Abre a câmera em tela cheia; cada código lido chama [onCode].
/// A mesma etiqueta só é aceita de novo após 1,5 s (evita contar duas vezes sem querer).
Future<void> showCameraScanner(BuildContext context, Future<void> Function(String code) onCode) {
  return Navigator.of(context).push(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => _CameraScannerPage(onCode: onCode),
  ));
}

class _CameraScannerPage extends StatefulWidget {
  const _CameraScannerPage({required this.onCode});
  final Future<void> Function(String code) onCode;

  @override
  State<_CameraScannerPage> createState() => _CameraScannerPageState();
}

class _CameraScannerPageState extends State<_CameraScannerPage> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    formats: const [
      BarcodeFormat.ean13, BarcodeFormat.ean8, BarcodeFormat.upcA, BarcodeFormat.upcE,
      BarcodeFormat.code128, BarcodeFormat.code39, BarcodeFormat.itf, BarcodeFormat.qrCode,
      BarcodeFormat.dataMatrix,
    ],
  );
  String? _lastCode;
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _count = 0;
  String _status = 'Aponte para o código de barras';

  Future<void> _onDetect(BarcodeCapture capture) async {
    final code = capture.barcodes.firstOrNull?.rawValue?.trim();
    if (code == null || code.isEmpty) return;
    final now = DateTime.now();
    if (code == _lastCode && now.difference(_lastAt) < const Duration(milliseconds: 1500)) return;
    _lastCode = code;
    _lastAt = now;
    HapticFeedback.mediumImpact();
    await widget.onCode(code);
    if (mounted) setState(() { _count++; _status = 'Lido: $code'; });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('$_count leitura(s)'),
        actions: [
          IconButton(icon: const Icon(Icons.flash_on), onPressed: () => _controller.toggleTorch()),
        ],
      ),
      body: Stack(children: [
        MobileScanner(controller: _controller, onDetect: _onDetect),
        Center(
          child: Container(
            width: 280,
            height: 160,
            decoration: BoxDecoration(border: Border.all(color: Colors.white70, width: 2), borderRadius: BorderRadius.circular(12)),
          ),
        ),
        Positioned(
          left: 16, right: 16, bottom: 32,
          child: Column(children: [
            Text(_status, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 16)),
            const SizedBox(height: 16),
            FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Concluir leitura pela câmera')),
          ]),
        ),
      ]),
    );
  }
}

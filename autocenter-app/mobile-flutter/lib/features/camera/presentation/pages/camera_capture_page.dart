import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/camera_session_provider.dart';
import '../../camera_engine_service.dart';

import '../../../vehicle/domain/entities/vehicle.dart';

class CameraCapturePage extends StatefulWidget {
  final Vehicle? vehicle;

  const CameraCapturePage({Key? key, this.vehicle}) : super(key: key);

  @override
  State<CameraCapturePage> createState() => _CameraCapturePageState();
}

class _CameraCapturePageState extends State<CameraCapturePage> {
  late CameraController _controller;
  bool _isInit = false;
  bool _isCapturing = false;
  final CameraEngineService _engine = CameraEngineService();

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;

    final backCamera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    // Resolução High para evitar problemas no visor, porém na gravação será comprimida pesadamente
    _controller = CameraController(backCamera, ResolutionPreset.high, enableAudio: false);
    
    await _controller.initialize();
    if (!mounted) return;
    
    setState(() => _isInit = true);
  }

  @override
  void dispose() {
    if (_isInit) {
      _controller.dispose();
    }
    super.dispose();
  }

  Future<void> _takePicture() async {
    final session = context.read<CameraSessionProvider>();
    if (!session.canTakePicture) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🛑 Limite máximo de 10 fotos atingido para proteger a cota da Nuvem e prefinir OOM.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    if (_isCapturing || !_isInit) return;

    setState(() => _isCapturing = true);

    try {
      final XFile pic = await _controller.takePicture();
      // O EngineService aplica a compressão forte para manter as 10 imagens leves no buffer offline
      final compressedPath = await _engine.compressAndSave(pic.path);
      
      if (compressedPath != null) {
        session.addPhoto(compressedPath);
      }
    } catch (_) {
      // Falha transparente no visor
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInit) {
      return const Scaffold(
         backgroundColor: Colors.black,
         body: Center(child: CircularProgressIndicator(color: Color(0xFFF26822))),
      );
    }
    
    final session = context.watch<CameraSessionProvider>();

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Câmera Native Render (Touch Area Total)
          CameraPreview(_controller),
          
          // 2. Máscara Vazada de Carro - O Guia Visual do Mecânico
          _buildVisualGuide(session.photosCount),

          // 3. Status Bar (Contador vs Teto)
          Positioned(
            top: 60,
            left: 20,
            right: 20,
            child: Row(
               mainAxisAlignment: MainAxisAlignment.spaceBetween,
               children: [
                 Container(
                   decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black54),
                   child: IconButton(
                     icon: const Icon(Icons.close, color: Colors.white, size: 28),
                     onPressed: () => Navigator.pop(context),
                   ),
                 ),
                 Container(
                   padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                   decoration: BoxDecoration(
                     color: session.canTakePicture ? Colors.black54 : Colors.red,
                     borderRadius: BorderRadius.circular(20),
                   ),
                   child: Text(
                     '${session.photosCount} / ${session.maxPhotos}',
                     style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                   ),
                 )
               ]
            ),
          ),

          // 4. Painel de Controle Inferior
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Column(
              children: [
                // Etiqueta Direcionadora (Frente, Placa, etc)
                Container(
                   padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                   margin: const EdgeInsets.only(bottom: 24),
                   decoration: BoxDecoration(
                     color: const Color(0xFFF26822),
                     borderRadius: BorderRadius.circular(30),
                   ),
                   child: Text(
                     session.currentStageGuide,
                     style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                   ),
                ),
                
                // Botão de Captura (Touch Area Fitts' Law Rule)
                GestureDetector(
                  onTap: _takePicture,
                  child: Container(
                    height: 85,
                    width: 85,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 4),
                      color: session.canTakePicture ? Colors.transparent : Colors.grey.withValues(alpha: 0.5),
                    ),
                    child: Center(
                      child: AnimatedContainer(
                         duration: const Duration(milliseconds: 150),
                         height: _isCapturing ? 60 : 70,
                         width: _isCapturing ? 60 : 70,
                         decoration: BoxDecoration(
                           shape: BoxShape.circle,
                           color: session.canTakePicture ? Colors.white : Colors.white54,
                         ),
                      ),
                    ),
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Fase 2 - Aborto de Atendimento com Status=CANCELADO
                OutlinedButton.icon(
                  onPressed: () {
                    session.resetSession();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Atendimento CANCELADO. Fila será atualizada.')),
                    );
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.cancel_outlined, color: Colors.white70),
                  label: const Text('Cancelar Atendimento', style: TextStyle(color: Colors.white70)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white30),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Desenha um Holograma na tela como silhueta para ajudar no enquadramento
  Widget _buildVisualGuide(int photoIndex) {
    return Center(
      child: IgnorePointer(
        child: Container(
          width: MediaQuery.of(context).size.width * 0.85,
          height: MediaQuery.of(context).size.height * 0.65,
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFF26822).withValues(alpha: 0.4), width: 2),
            borderRadius: BorderRadius.circular(24),
          ),
          child: CustomPaint(
            painter: _CarSilhouettePainter(photoIndex),
            child: Center(
              child: Opacity(
                opacity: 0.15,
                child: Icon(
                  _getGuideIcon(photoIndex),
                  color: Colors.white, 
                  size: 150,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  IconData _getGuideIcon(int index) {
    switch (index) {
      case 0: return Icons.directions_car_filled_outlined; // Frente
      case 1: return Icons.compare_arrows_rounded;         // Esq
      case 2: return Icons.directions_car_filled_outlined; // Traseira
      case 3: return Icons.compare_arrows_rounded;         // Dir
      case 4: return Icons.speed_rounded;                  // Painel
      default: return Icons.center_focus_strong_rounded;   // Avarias Livres
    }
  }
}

/// Custom UI: Renderiza as guias de mira no estilo HUD (Heads Up Display)
class _CarSilhouettePainter extends CustomPainter {
  final int stage;
  _CarSilhouettePainter(this.stage);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
      
    // Implementaçao manual de Dash simplificada ou linhas retas
    paint.strokeWidth = 2;
    
    final path = Path();
    final double w = size.width;
    final double h = size.height;

    // Dependendo do Stage, desenha linhas guias holográficas diferentes
    if (stage == 0 || stage == 2) {
      // Frente / Traseira (Desenha retangulos para placa e faróis)
      path.addRect(Rect.fromLTWH(w * 0.3, h * 0.8, w * 0.4, h * 0.1)); // Placa
      path.addOval(Rect.fromLTWH(w * 0.1, h * 0.5, w * 0.2, h * 0.15)); // Farol Esq
      path.addOval(Rect.fromLTWH(w * 0.7, h * 0.5, w * 0.2, h * 0.15)); // Farol Dir
    } else if (stage == 1 || stage == 3) {
      // Laterais (Desenha arcos representando as 2 rodas inferior)
      path.addArc(Rect.fromLTWH(w * 0.15, h * 0.75, w * 0.25, h * 0.15), 3.14, 3.14); // Roda Traz/Frente
      path.addArc(Rect.fromLTWH(w * 0.6, h * 0.75, w * 0.25, h * 0.15), 3.14, 3.14);
      path.moveTo(0, h * 0.82);
      path.lineTo(w, h * 0.82); // Chão
    } else if (stage == 4) {
      // Painel (Painel de instrumentos)
      path.addArc(Rect.fromLTWH(w * 0.2, h * 0.3, w * 0.6, h * 0.4), 3.14, 3.14); // Hodometro
    } else {
      // Livre: Mira Simples Central
      path.moveTo(w / 2, h * 0.3); path.lineTo(w / 2, h * 0.7);
      path.moveTo(w * 0.3, h / 2); path.lineTo(w * 0.7, h / 2);
      canvas.drawCircle(Offset(w / 2, h / 2), 40, paint);
    }
    
    // Draw com efeito de mira opaca
    canvas.drawPath(path, paint);
    
    // Bordas (Cantoneiras estilo Câmera Profissional)
    final cornerPaint = Paint()..color = const Color(0xFFF26822)..style = PaintingStyle.stroke..strokeWidth = 4;
    double cLen = 30;
    // Top Left
    canvas.drawLine(const Offset(0, 0), Offset(cLen, 0), cornerPaint);
    canvas.drawLine(const Offset(0, 0), Offset(0, cLen), cornerPaint);
    // Top Right
    canvas.drawLine(Offset(w, 0), Offset(w - cLen, 0), cornerPaint);
    canvas.drawLine(Offset(w, 0), Offset(w, cLen), cornerPaint);
    // Bottom Left
    canvas.drawLine(Offset(0, h), Offset(cLen, h), cornerPaint);
    canvas.drawLine(Offset(0, h), Offset(0, h - cLen), cornerPaint);
    // Bottom Right
    canvas.drawLine(Offset(w, h), Offset(w - cLen, h), cornerPaint);
    canvas.drawLine(Offset(w, h), Offset(w, h - cLen), cornerPaint);
  }

  @override
  bool shouldRepaint(covariant _CarSilhouettePainter oldDelegate) => oldDelegate.stage != stage;
}

import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class SignatureCanvas extends StatefulWidget {
  final ValueChanged<ui.Image?> onSave;

  const SignatureCanvas({Key? key, required this.onSave}) : super(key: key);

  @override
  State<SignatureCanvas> createState() => _SignatureCanvasState();
}

class _SignatureCanvasState extends State<SignatureCanvas> {
  final List<Offset?> _points = [];

  void _clear() {
    setState(() {
      _points.clear();
    });
  }

  Future<void> _save() async {
    if (_points.isEmpty) {
      widget.onSave(null);
      return;
    }

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 300, 150));
    
    // Draw white background
    final bgPaint = Paint()..color = Colors.white;
    canvas.drawRect(const Rect.fromLTWH(0, 0, 300, 150), bgPaint);

    // Draw drawing stroke
    final paint = Paint()
      ..color = Colors.black
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3.0;

    for (int i = 0; i < _points.length - 1; i++) {
      if (_points[i] != null && _points[i + 1] != null) {
        canvas.drawLine(_points[i]!, _points[i + 1]!, paint);
      }
    }

    final picture = recorder.endRecording();
    final img = await picture.toImage(300, 150);
    widget.onSave(img);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 300,
          height: 150,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.grey.shade400),
            borderRadius: BorderRadius.circular(8),
          ),
          child: GestureDetector(
            onPanUpdate: (details) {
              final RenderBox renderBox = context.findRenderObject() as RenderBox;
              final localPosition = renderBox.globalToLocal(details.globalPosition);
              // Constrain points inside canvas bounds
              if (localPosition.dx >= 0 && localPosition.dx <= 300 &&
                  localPosition.dy >= 0 && localPosition.dy <= 150) {
                setState(() {
                  _points.add(localPosition);
                });
              }
            },
            onPanEnd: (details) {
              setState(() {
                _points.add(null);
              });
            },
            child: CustomPaint(
              painter: _SignaturePainter(_points),
              size: Size.infinite,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            TextButton(
              onPressed: _clear,
              child: const Text('Limpar'),
            ),
            ElevatedButton(
              onPressed: _save,
              child: const Text('Confirmar Assinatura'),
            ),
          ],
        ),
      ],
    );
  }
}

class _SignaturePainter extends CustomPainter {
  final List<Offset?> points;

  _SignaturePainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3.0;

    for (int i = 0; i < points.length - 1; i++) {
      if (points[i] != null && points[i + 1] != null) {
        canvas.drawLine(points[i]!, points[i + 1]!, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) => true;
}

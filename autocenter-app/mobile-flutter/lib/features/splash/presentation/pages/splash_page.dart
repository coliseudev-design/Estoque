import 'dart:math';
import 'package:flutter/material.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/auth/auth_token_manager.dart';
import '../../../../core/network/sync_service.dart';
import '../../../auth/presentation/pages/auth_gate.dart';

/// SplashScreen — Tela de apresentação de alto impacto visual herdada do Coliseu Sales
/// Adaptada com a lógica de incialização do AutoCenter
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> with TickerProviderStateMixin {
  // ── Cores do sistema ────────────────────────────────────────────────────
  static const _blue = Color(0xFF2A7FC0);
  static const _blueLight = Color(0xFF4DA3E0);
  static const _bgColor = Color(0xFFF9FAFB);
  static const _textDark = Color(0xFF3D3D3D);

  // ── Controladores ──────────────────────────────────────────────────────
  late AnimationController _stripesCtrl;
  late AnimationController _logoCtrl;
  late AnimationController _barCtrl;
  late AnimationController _typeCtrl;
  late AnimationController _loaderCtrl;
  late AnimationController _exitCtrl;

  // ── Animações ──────────────────────────────────────────────────────────
  late Animation<double> _stripesAnim;
  late Animation<double> _logoScale;
  late Animation<double> _logoOpacity;
  late Animation<double> _barWidth;
  late Animation<double> _barOpacity;
  late Animation<double> _typeProgress;
  late Animation<double> _loaderOpacity;
  late Animation<double> _exitOpacity;

  final _typeText = 'Seu autocenter na palma da mão.';
  bool _isAppInitialized = false;
  Widget? _nextScreen;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _startSequence();
    _initializeApp();
  }

  void _setupAnimations() {
    // ── Listras diagonais — loop infinito ────────────────────────────────
    _stripesCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    _stripesAnim = Tween<double>(begin: 0, end: 1).animate(_stripesCtrl);

    // ── Logo — bounce entrance ──────────────────────────────────────────
    _logoCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _logoScale = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _logoCtrl, curve: Curves.elasticOut));
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _logoCtrl, curve: const Interval(0.0, 0.3)));

    // ── Barra azul decorativa ───────────────────────────────────────────
    _barCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _barWidth = Tween<double>(begin: 0, end: 50).animate(
        CurvedAnimation(parent: _barCtrl, curve: Curves.easeOutCubic));
    _barOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _barCtrl, curve: Curves.easeIn));

    // ── Typewriter text ─────────────────────────────────────────────────
    _typeCtrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _typeText.length * 70),
    );
    _typeProgress = Tween<double>(begin: 0, end: _typeText.length.toDouble())
        .animate(CurvedAnimation(parent: _typeCtrl, curve: Curves.easeInOut));

    // ── Loader pulsante ─────────────────────────────────────────────────
    _loaderCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _loaderOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _loaderCtrl, curve: Curves.easeIn));

    // ── Saída ────────────────────────────────────────────────────────────
    _exitCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _exitOpacity = Tween<double>(begin: 1.0, end: 0.0).animate(
        CurvedAnimation(parent: _exitCtrl, curve: Curves.easeIn));
  }

  Future<void> _initializeApp() async {
    try {
      await SyncService.initialize();

      final tokenManager = getIt<AuthTokenManager>();
      final apiClient = getIt<ApiClient>();
      final isActivated = await tokenManager.isActivated();

      if (isActivated) {
        final savedUrl = await tokenManager.getBaseUrl();
        if (savedUrl != null && savedUrl.isNotEmpty) {
          apiClient.updateBaseUrl('$savedUrl/api');
        }
      }

      _nextScreen = const AuthGate();
    } catch (e, stackTrace) {
      debugPrint('Erro de inicialização: $e\n$stackTrace');
      _nextScreen = Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 64),
                const SizedBox(height: 16),
                const Text(
                  'Erro crítico na inicialização do sistema.',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$e',
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isAppInitialized = true;
        });
      }
    }
  }

  Future<void> _startSequence() async {
    await Future.delayed(const Duration(milliseconds: 300));
    _logoCtrl.forward();
    
    await Future.delayed(const Duration(milliseconds: 700));
    _barCtrl.forward();
    
    await Future.delayed(const Duration(milliseconds: 400));
    _typeCtrl.forward();
    
    await Future.delayed(Duration(milliseconds: _typeText.length * 70 + 300));
    _loaderCtrl.forward();
    
    await Future.delayed(const Duration(milliseconds: 1500));

    // Aguarda finalização da inicialização (reduz chance de entrar com dados faltantes)
    while (!_isAppInitialized) {
      await Future.delayed(const Duration(milliseconds: 200));
    }

    await _exitCtrl.forward();

    if (!mounted || _nextScreen == null) return;
    
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => _nextScreen!,
        transitionDuration: Duration.zero,
      ),
    );
  }

  @override
  void dispose() {
    _stripesCtrl.dispose();
    _logoCtrl.dispose();
    _barCtrl.dispose();
    _typeCtrl.dispose();
    _loaderCtrl.dispose();
    _exitCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      body: AnimatedBuilder(
        animation: Listenable.merge([
          _stripesCtrl,
          _logoCtrl,
          _barCtrl,
          _typeCtrl,
          _loaderCtrl,
          _exitCtrl,
        ]),
        builder: (_, __) => Opacity(
          opacity: _exitOpacity.value,
          child: Stack(
            children: [
              // ── Listras diagonais animadas ─────────────────────────────
              Positioned.fill(
                child: CustomPaint(
                  painter: _DiagonalStripesPainter(
                    progress: _stripesAnim.value,
                    color: _blue,
                  ),
                ),
              ),

              // ── Conteúdo central ──────────────────────────────────────
              SafeArea(
                child: Column(
                  children: [
                    const Spacer(flex: 3),

                    // ── Logo com bounce ──────────────────────────────────
                    FadeTransition(
                      opacity: _logoOpacity,
                      child: ScaleTransition(
                        scale: _logoScale,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 40),
                            child: Image.asset(
                              'assets/images/coliseu_logo.png', // Usando o logo principal mantido no app
                              width: 300,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) => 
                                 const Icon(Icons.auto_awesome_motion_rounded, size: 80, color: Color(0xFF2A7FC0)),
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 28),

                    // ── Barra azul animada ───────────────────────────────
                    Opacity(
                      opacity: _barOpacity.value,
                      child: Container(
                        width: _barWidth.value,
                        height: 3,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [_blue, _blueLight],
                          ),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── Typewriter text ──────────────────────────────────
                    SizedBox(
                      height: 30,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _typeText.substring(0, _typeProgress.value.floor().clamp(0, _typeText.length)),
                            style: const TextStyle(
                              color: _textDark,
                              fontSize: 18, // Ligeiramente reduzido para frase mais longa
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.5,
                            ),
                          ),
                          if (_typeProgress.value < _typeText.length)
                            const _BlinkingCursor(color: _blue),
                        ],
                      ),
                    ),

                    const Spacer(flex: 4),

                    // ── Loader pulsante ──────────────────────────────────
                    Opacity(
                      opacity: _loaderOpacity.value,
                      child: const Padding(
                        padding: EdgeInsets.only(bottom: 48),
                        child: _PulsingDots(color: _blue),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Diagonal Stripes Painter
// ─────────────────────────────────────────────────────────────────────────────

class _DiagonalStripesPainter extends CustomPainter {
  final double progress;
  final Color color;

  _DiagonalStripesPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    const stripeCount = 6;
    final stripeWidth = size.width * 0.12;
    final totalSpan = size.width + size.height;
    final spacing = totalSpan / (stripeCount - 1);

    for (var i = 0; i < stripeCount; i++) {
      final opacity = const [0.03, 0.05, 0.04, 0.06, 0.03, 0.05][i];
      final width = stripeWidth * const [0.8, 1.2, 0.6, 1.0, 0.5, 0.9][i];

      paint.color = color.withValues(alpha: opacity);

      final baseOffset = i * spacing - totalSpan * 0.1;
      final animOffset = progress * spacing * 0.6;
      final offset = baseOffset + animOffset;

      final path = Path()
        ..moveTo(offset, 0)
        ..lineTo(offset + width, 0)
        ..lineTo(offset + width - size.height, size.height)
        ..lineTo(offset - size.height, size.height)
        ..close();

      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_DiagonalStripesPainter old) => old.progress != progress;
}

// ─────────────────────────────────────────────────────────────────────────────
// Blinking Cursor
// ─────────────────────────────────────────────────────────────────────────────

class _BlinkingCursor extends StatefulWidget {
  final Color color;
  const _BlinkingCursor({required this.color});

  @override
  State<_BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<_BlinkingCursor>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _ctrl,
      child: Container(
        width: 2,
        height: 20,
        margin: const EdgeInsets.only(left: 1),
        color: widget.color,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pulsing Dots
// ─────────────────────────────────────────────────────────────────────────────

class _PulsingDots extends StatefulWidget {
  final Color color;
  const _PulsingDots({required this.color});

  @override
  State<_PulsingDots> createState() => _PulsingDotsState();
}

class _PulsingDotsState extends State<_PulsingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          final delay = i * 0.2;
          final t = ((_ctrl.value - delay) % 1.0).clamp(0.0, 1.0);
          final scale = 0.5 + 0.5 * sin(t * pi);

          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color.withValues(alpha: 0.3 + 0.7 * scale),
            ),
          );
        }),
      ),
    );
  }
}

/// connectivity_banner.dart — Indicador visual de modo offline (M1).
///
/// Widget que exibe um banner animado quando o app perde a conectividade.
/// Deve ser envolvido em torno do conteúdo principal do Scaffold.
///
/// Uso:
/// ```dart
/// Scaffold(
///   body: Column(children: [
///     ConnectivityBanner(),
///     Expanded(child: MyContent()),
///   ]),
/// )
/// ```
library;

import 'dart:async';
import 'package:flutter/material.dart';
import '../network/connectivity_service.dart';

class ConnectivityBanner extends StatefulWidget {
  final ConnectivityService connectivity;
  const ConnectivityBanner({super.key, required this.connectivity});

  @override
  State<ConnectivityBanner> createState() => _ConnectivityBannerState();
}

class _ConnectivityBannerState extends State<ConnectivityBanner>
    with SingleTickerProviderStateMixin {
  bool _isOffline = false;
  bool _justReconnected = false;
  StreamSubscription<ConnectivityStatus>? _sub;
  late AnimationController _anim;
  late Animation<Offset> _slide;
  Timer? _reconTimer;

  @override
  void initState() {
    super.initState();

    _anim = AnimationController(duration: const Duration(milliseconds: 300), vsync: this);
    _slide = Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero)
        .animate(CurvedAnimation(parent: _anim, curve: Curves.easeOut));

    // Escuta status de conectividade
    _sub = widget.connectivity.status.listen((status) {
      final isOnline = status == ConnectivityStatus.online;
      final wasOffline = _isOffline;
      setState(() => _isOffline = !isOnline);

      if (!isOnline) {
        _anim.forward();
        _reconTimer?.cancel();
      } else if (wasOffline) {
        // Reconectou — mostra banner verde por 3s
        setState(() => _justReconnected = true);
        _anim.forward();
        _reconTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) {
            _anim.reverse();
            setState(() { _isOffline = false; _justReconnected = false; });
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _anim.dispose();
    _reconTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isOffline && !_justReconnected) return const SizedBox.shrink();

    final isRecon = _justReconnected && !_isOffline;
    final bg    = isRecon ? Colors.green.shade700 : Colors.red.shade700;
    final icon  = isRecon ? Icons.wifi           : Icons.wifi_off;
    final msg   = isRecon ? 'Conexão restaurada!'  : 'Sem conexão — modo offline';

    return SlideTransition(
      position: _slide,
      child: Material(
        color: bg,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(msg,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
              if (_isOffline)
                const SizedBox(
                  width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

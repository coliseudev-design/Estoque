import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../../data/models/seller_model.dart';
import '../../../../features/vehicle/presentation/pages/vehicle_search_page.dart';
import '../../../../features/home/presentation/pages/home_scaffold.dart';
import '../../../../core/network/sync_service.dart';
import 'setup_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with SingleTickerProviderStateMixin {
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticOut),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AuthProvider>().loadSellers();
    });
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  void _triggerShake() {
    _shakeController.forward(from: 0);
    HapticFeedback.heavyImpact();
  }

  void _doLogin(AuthProvider auth) async {
    final success = await auth.loginWithPin();

    if (success && mounted) {
      // Dispara o download inicial das bases de dados offline principal na navegação inicial
      SyncService.registerCustomerSync();
      SyncService.registerCatalogSync();
      
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScaffold())
      );
    } else if (!success && mounted) {
      _triggerShake();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(auth.errorMessage ?? 'PIN incorreto. Tente novamente.'),
          backgroundColor: Colors.redAccent,
        )
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryBlue = Color(0xFF0F3A70);
    const accentOrange = Color(0xFFF26822);
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: primaryBlue,
      body: SafeArea(
        child: auth.state == AuthState.loading && auth.sellers.isEmpty
            ? const Center(
                child: CircularProgressIndicator(color: Colors.white),
              )
            : auth.selectedSeller == null
                ? _buildSellerSelectionList(auth)
                : _buildPinEntryScreen(auth, accentOrange),
      ),
    );
  }

  Widget _buildSellerSelectionList(AuthProvider auth) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 48),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SizedBox(width: 48), // Espaçador para equilibrar o ícone da direita
              Expanded(
                child: Center(
                  child: Column(
                    children: [
                      const Icon(
                        Icons.security_rounded,
                        size: 64,
                        color: Colors.white,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Coliseu Sistemas',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Text(
                        'Auto Center Vendas — Seleção de Usuário',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.settings_outlined, color: Colors.white70),
                tooltip: 'Configurações do Servidor',
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SetupPage()),
                  );
                  auth.loadSellers();
                },
              ),
            ],
          ),
          const SizedBox(height: 32),
          const Text(
            'Selecione seu usuário:',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          if (auth.sellers.isEmpty)
            Center(
              child: Card(
                color: Colors.white.withValues(alpha: 0.1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Colors.white70, size: 48),
                      const SizedBox(height: 12),
                      Text(
                        auth.errorMessage ?? 'Nenhum vendedor encontrado localmente.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF26822),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () => auth.loadSellers(),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Sincronizar Vendedores'),
                      ),
                      const SizedBox(height: 12),
                      TextButton.icon(
                        onPressed: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const SetupPage()),
                          );
                          auth.loadSellers();
                        },
                        icon: const Icon(Icons.settings_outlined, color: Colors.white70, size: 18),
                        label: const Text(
                          'Configurar Servidor / API Key',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                itemCount: auth.sellers.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final seller = auth.sellers[index];
                  final initial = seller.name.isNotEmpty ? seller.name[0].toUpperCase() : '?';
                  return Card(
                    color: Colors.white.withValues(alpha: 0.1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      onTap: () => auth.selectSeller(seller),
                      leading: CircleAvatar(
                        backgroundColor: Colors.white.withValues(alpha: 0.2),
                        child: Text(
                          initial,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Text(
                        seller.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      trailing: const Icon(
                        Icons.chevron_right,
                        color: Colors.white70,
                      ),
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildPinEntryScreen(AuthProvider auth, Color accentColor) {
    final seller = auth.selectedSeller!;
    final initial = seller.name.isNotEmpty ? seller.name[0].toUpperCase() : '?';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        children: [
          const SizedBox(height: 24),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                onPressed: () => auth.selectSeller(null),
              ),
            ],
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  CircleAvatar(
                    radius: 36,
                    backgroundColor: Colors.white.withValues(alpha: 0.15),
                    child: Text(
                      initial,
                      style: const TextStyle(
                        fontSize: 28,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    seller.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Digite seu PIN de acesso',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 24),
                  AnimatedBuilder(
                    animation: _shakeAnimation,
                    builder: (context, child) {
                      double offset = 0.0;
                      if (auth.state == AuthState.error) {
                        // Elastic wobble
                        offset = (math.sin(_shakeAnimation.value * math.pi * 3.0) * 15.0) * (1.0 - _shakeAnimation.value);
                      }
                      return Transform.translate(
                        offset: Offset(offset, 0),
                        child: child,
                      );
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(6, (i) {
                        final isFilled = i < auth.currentPin.length;
                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isFilled
                                ? (auth.state == AuthState.error ? Colors.redAccent : Colors.white)
                                : Colors.white24,
                            border: Border.all(
                              color: isFilled ? Colors.white : Colors.white38,
                              width: 1.5,
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                  const SizedBox(height: 32),
                  _buildNumericKeyboard(auth),
                  const SizedBox(height: 32),
                  if (auth.state == AuthState.loading)
                    CircularProgressIndicator(color: accentColor)
                  else
                    SizedBox(
                      width: 200,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accentColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(25),
                          ),
                          elevation: 0,
                        ),
                        onPressed: auth.currentPin.length >= 3 ? () => _doLogin(auth) : null,
                        child: const Text(
                          'ENTRAR',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNumericKeyboard(AuthProvider auth) {
    final keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', '⌫'],
    ];

    return Column(
      children: keys.map((row) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: row.map((key) {
              if (key.isEmpty) {
                return const SizedBox(width: 72, height: 72);
              }

              final isBackspace = key == '⌫';
              return SizedBox(
                width: 72,
                height: 72,
                child: TextButton(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    if (isBackspace) {
                      auth.removeLastDigit();
                    } else {
                      auth.appendDigit(key);
                    }
                  },
                  style: TextButton.styleFrom(
                    shape: const CircleBorder(),
                    backgroundColor: Colors.white.withValues(alpha: 0.1),
                    foregroundColor: Colors.white,
                  ),
                  child: isBackspace
                      ? const Icon(Icons.backspace_outlined, color: Colors.white)
                      : Text(
                          key,
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                          ),
                        ),
                ),
              );
            }).toList(),
          ),
        );
      }).toList(),
    );
  }
}

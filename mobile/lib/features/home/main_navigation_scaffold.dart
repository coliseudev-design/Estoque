/// MainNavigationScaffold ”” Shell principal com NavigationBar moderna.
///
/// Tabs:
/// 0: ðŸ  Início      ”” Dashboard com KPIs, ações rápidas, últimos pedidos
/// 1: ðŸ“¦ Catálogo     ”” Lista de produtos para adicionar ao carrinho
/// 2: ðŸ‘¥ Clientes     ”” Consulta e cadastro de clientes
/// 3: ðŸ“‹ Pedidos      ”” Histórico de pedidos filtrados por período
/// 4: ðŸ‘¤ Perfil       ”” Perfil, sync queue, configurações, logout
library;

import 'dart:async';
import 'package:flutter/material.dart';

import 'package:get_it/get_it.dart';
import '../../core/cart/cart_notifier.dart';
import '../../core/database/database_helper.dart';
import '../../core/network/auto_sync_service.dart';
import '../../core/network/connectivity_service.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_typography.dart';
import '../home/home_screen.dart';
import '../performance/seller_performance_screen.dart';
import '../catalog/catalog_screen.dart';
import '../customers/customers_screen.dart';
import '../order_history/order_history_screen.dart';
import '../new_order/new_order_screen.dart';
import '../profile/seller_profile_screen.dart';
import '../../core/network/connectivity_banner.dart';
import '../../core/services/order_notification_service.dart';

class MainNavigationScaffold extends StatefulWidget {
  const MainNavigationScaffold({super.key});

  @override
  State<MainNavigationScaffold> createState() => _MainNavigationScaffoldState();
}

class _MainNavigationScaffoldState extends State<MainNavigationScaffold> with WidgetsBindingObserver {
  int _currentIndex = 0;
  late final CartNotifier       _cart;
  late final AutoSyncService    _autoSync;
  late final ConnectivityService _connectivity;
  StreamSubscription<ConnectivityStatus>? _connectivitySub;
  ConnectivityStatus _lastConnectivity = ConnectivityStatus.offline;

  /// Contagem de pedidos com erro na fila de sync.
  int _errorCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cart          = GetIt.I<CartNotifier>();
    _autoSync      = GetIt.I<AutoSyncService>();
    _connectivity  = GetIt.I<ConnectivityService>();
    _lastConnectivity = _connectivity.currentStatus;
    _cart.addListener(_onCartChanged);

    _connectivitySub = _connectivity.status.listen(_onConnectivityChanged);

    _refreshErrorCount();
    _autoSync.stateNotifier.addListener(_onSyncStateChanged);

    // Inicia polling de confirmações de pedidos (M3)
    GetIt.I<OrderNotificationService>().startPolling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cart.removeListener(_onCartChanged);
    _autoSync.stateNotifier.removeListener(_onSyncStateChanged);
    _connectivitySub?.cancel();
    // Para o polling ao sair da tela principal (ex: logout)
    GetIt.I<OrderNotificationService>().stopPolling();
    super.dispose();
  }

  void _onCartChanged() => setState(() {});

  Future<void> _refreshErrorCount() async {
    final db    = GetIt.I<DatabaseHelper>();
    final rows  = await db.getSyncQueue('error');
    if (mounted) setState(() => _errorCount = rows.length);
  }

  void _onSyncStateChanged() {
    final state = _autoSync.stateNotifier.value;
    if (state == AutoSyncState.success || state == AutoSyncState.partial) {
      _refreshErrorCount();
    }
  }

  void _onConnectivityChanged(ConnectivityStatus status) {
    final wasOffline = _lastConnectivity == ConnectivityStatus.offline;
    final isOnline   = status == ConnectivityStatus.online;
    _lastConnectivity = status;
    if (wasOffline && isOnline && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.cloud_done_outlined, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text('Conexão restaurada ”” sincronizando...',
                style: AppTypography.body.copyWith(color: Colors.white)),
            ],
          ),
          backgroundColor: AppColors.success,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Abre a tela de criação de novo pedido.
  /// Reutilizado pelo FAB da aba Pedidos e pelo botão "Novo Pedido" do Início.
  Future<void> _openNewOrder(BuildContext ctx) async {
    _cart.clear();
    final result = await Navigator.push<bool>(
      ctx,
      MaterialPageRoute(builder: (_) => NewOrderScreen(cart: _cart)),
    );
    if (result == true && mounted) {
      setState(() => _currentIndex = 4); // Switch to Pedidos tab
    }
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // Build
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: _currentIndex == 0,
      onPopInvoked: (didPop) {
        if (didPop) return;
        if (_currentIndex != 0) {
          setState(() => _currentIndex = 0);
        }
      },
      child: Scaffold(
        backgroundColor: isDark ? AppColors.surfaceDM : AppColors.surfaceSecondary,

        body: Column(
        children: [
          // Banner animado de status de conexão (M1)
          ConnectivityBanner(
            connectivity: GetIt.I<ConnectivityService>(),
          ),
          Expanded(
            child: SafeArea(
              // bottom: true (padrão) — SafeArea respeita MediaQuery.viewPadding.bottom.
              // Em edgeToEdge com 3-button nav: adiciona padding da barra virtual.
              // Em gesture nav (sem botões): padding é zero. Adaptativo automaticamente.
              child: IndexedStack(
                index: _currentIndex,
                children: [
                  // Tab 0 ”” Início (Dashboard)
                  HomeScreen(
                    onNewOrder: () => _openNewOrder(context),
                    onViewOrders: () => setState(() => _currentIndex = 4),
                  ),

                  // Tab 1 ”” Desempenho
                  const SellerPerformanceScreen(),

                  // Tab 2 ”” Catálogo
                  const CatalogScreen(),

                  // Tab 3 ”” Clientes
                  const CustomersScreen(),

                  // Tab 4 ”” Histórico de Pedidos
                  OrderHistoryScreen(cart: _cart),

                  // Tab 5 ”” Perfil
                  const SellerProfileScreen(),
                ],
              ),
            ),
          ),
        ],
      ),

      // ── Bottom Navigation customizada (sem labels, ícones coloridos) ──────
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          height: 76,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
            border: Border(
              top: BorderSide(
                color: isDark ? AppColors.borderDark : AppColors.border,
                width: 0.5,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 12,
                offset: const Offset(0, -3),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _navItem(0, Icons.home_rounded,              Icons.home_outlined,               const Color(0xFF6C63FF)), // Início – Casa
              _navItem(1, Icons.trending_up_rounded,       Icons.trending_up_outlined,        const Color(0xFF00B894)), // Desempenho – Seta crescendo
              _navItem(2, Icons.local_offer_rounded,       Icons.local_offer_outlined,        const Color(0xFFE17055)), // Catálogo – Etiqueta
              _navItem(3, Icons.groups_rounded,            Icons.groups_outlined,             const Color(0xFF0984E3)), // Clientes – Grupo
              _navItem(4, Icons.shopping_cart_checkout,    Icons.shopping_cart_outlined,      const Color(0xFFFDAB55)), // Pedidos – Carrinho+check
              _navItemProfile(5),                                                                                       // Perfil – rosa
            ],
          ),
        ),
      ),
      ),    // fecha Scaffold
      );    // fecha PopScope
  }

  Widget _navItem(int index, IconData selectedIcon, IconData unselectedIcon, Color color) {
    final selected = _currentIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _currentIndex = index),
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: AnimatedScale(
            scale: selected ? 1.1 : 1.0,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                gradient: selected
                    ? LinearGradient(
                        colors: [color, color.withOpacity(0.7)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: selected ? null : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                boxShadow: selected
                    ? [BoxShadow(color: color.withOpacity(0.35), blurRadius: 10, offset: const Offset(0, 4))]
                    : null,
              ),
              child: Icon(
                selected ? selectedIcon : unselectedIcon,
                color: selected ? Colors.white : const Color(0xFFB0BEC5),
                size: selected ? 28 : 26,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _navItemProfile(int index) {
    final selected = _currentIndex == index;
    const color = Color(0xFFE84393);

    Widget iconCore = Icon(
      selected ? Icons.verified_user_rounded : Icons.verified_user_outlined,
      color: selected ? Colors.white : const Color(0xFFB0BEC5),
      size: selected ? 28 : 26,
    );

    if (_errorCount > 0) {
      iconCore = Badge(
        label: Text(
          _errorCount > 9 ? '9+' : '$_errorCount',
          style: const TextStyle(color: Colors.white, fontSize: 10),
        ),
        backgroundColor: AppColors.error,
        child: iconCore,
      );
    }

    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _currentIndex = index),
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: AnimatedScale(
            scale: selected ? 1.1 : 1.0,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                gradient: selected
                    ? const LinearGradient(
                        colors: [Color(0xFFE84393), Color(0xFFAD1457)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: selected ? null : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                boxShadow: selected
                    ? [const BoxShadow(color: Color(0x55E84393), blurRadius: 10, offset: Offset(0, 4))]
                    : null,
              ),
              child: iconCore,
            ),
          ),
        ),
      ),
    );
  }
}

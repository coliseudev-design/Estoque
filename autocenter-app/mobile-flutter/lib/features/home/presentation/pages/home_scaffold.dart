import 'dart:async';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../../../core/design/app_colors.dart';
import '../../../vehicle/presentation/pages/vehicle_reception_page.dart';
import '../../../service_order/presentation/pages/active_orders_page.dart';
import '../../../customer/presentation/pages/customers_page.dart';
import '../../../services/presentation/pages/services_catalog_page.dart';
import '../../../profile/presentation/pages/profile_page.dart';

class HomeScaffold extends StatefulWidget {
  const HomeScaffold({Key? key}) : super(key: key);

  @override
  State<HomeScaffold> createState() => _HomeScaffoldState();
}

class _HomeScaffoldState extends State<HomeScaffold> {
  int _currentIndex = 0;
  bool _isOffline = false;
  late StreamSubscription<dynamic> _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    _checkInitialConnectivity();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((dynamic event) {
      _updateConnectivityStatus(event);
    });
  }

  Future<void> _checkInitialConnectivity() async {
    try {
      final result = await Connectivity().checkConnectivity();
      _updateConnectivityStatus(result);
    } catch (_) {}
  }

  void _updateConnectivityStatus(dynamic result) {
    bool isOffline = false;
    if (result is List) {
      isOffline = result.contains(ConnectivityResult.none) || result.isEmpty;
    } else {
      isOffline = result == ConnectivityResult.none;
    }
    if (mounted && _isOffline != isOffline) {
      setState(() {
        _isOffline = isOffline;
      });
    }
  }

  @override
  void dispose() {
    _connectivitySubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          if (_isOffline)
            Container(
              width: double.infinity,
              color: Colors.orange[800],
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: const SafeArea(
                bottom: false,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.wifi_off, color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Você está no modo offline. Salvando localmente.',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: IndexedStack(
              index: _currentIndex,
              children: [
                // Aba 0: Cadastro de Entrada / Busca de Placa
                const VehicleReceptionPage(),
                // Aba 1: Quadro de OS
                const ActiveOrdersPage(),
                // Aba 2: Catálogo Peças
                const ServicesCatalogPage(),
                // Aba 3: Clientes (Offline search / register)
                const CustomersPage(),
                // Aba 4: Perfil / Config
                const ProfilePage(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.car_rental_outlined),
            selectedIcon: Icon(Icons.car_rental),
            label: 'Entrada',
          ),
          NavigationDestination(
            icon: Icon(Icons.assignment_outlined),
            selectedIcon: Icon(Icons.assignment),
            label: 'OS',
          ),
          NavigationDestination(
            icon: Icon(Icons.build_circle_outlined),
            selectedIcon: Icon(Icons.build_circle),
            label: 'Catálogo',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Clientes',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }
}

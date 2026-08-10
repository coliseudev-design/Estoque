import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/design/app_colors.dart';
import '../../../../core/design/app_typography.dart';
import '../../../../core/network/auth/auth_token_manager.dart';
import '../../../auth/presentation/pages/activation_page.dart';
import '../../../auth/presentation/pages/auth_gate.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import 'reports_page.dart';
import '../../../../core/di/injection.dart';
import '../../../customer/data/datasources/customer_local_data_source.dart';
import '../../../customer/data/repositories/customer_repository_impl.dart';
import '../../../services/data/datasources/catalog_local_datasource.dart';
import '../../../services/data/repositories/catalog_repository_impl.dart';
import '../../../services/data/datasources/catalog_remote_datasource.dart';
import '../../../../core/network/sync_queue_service.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({Key? key}) : super(key: key);

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String _displayName = 'Vendedor';
  String _companyName = 'Coliseu Sistemas';
  String _deviceId = 'Dispositivo Autenticado';
  int _customerCount = 0;
  int _catalogCount = 0;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _loadAuthData();
  }

  Future<void> _loadAuthData() async {
    final tokenManager = AuthTokenManager();
    final companyName = await tokenManager.getCompanyName() ?? 'Coliseu AutoCenter';
    final deviceId = await tokenManager.getDeviceId() ?? 'Sessão Ativa';
    final vendedorName = await tokenManager.getVendedorName() ?? 'Vendedor';
    
    final customerLocal = getIt<CustomerLocalDataSource>();
    final catalogLocal = CatalogLocalDataSource();
    final customerCount = await customerLocal.getCustomerCount();
    final catalogCount = await catalogLocal.getCatalogCount();
    
    if (mounted) {
      setState(() {
        _displayName = vendedorName;
        _companyName = companyName;
        _deviceId = deviceId;
        _customerCount = customerCount;
        _catalogCount = catalogCount;
      });
    }
  }

  Future<void> _syncAll() async {
    setState(() => _isSyncing = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Iniciando sincronização completa...')),
    );
    
    try {
      // 1. Processa fila offline pendente (Upload de rascunhos / OS pendentes)
      await SyncQueueService.instance.processQueue();
      
      // 2. Sincroniza Clientes (PULL)
      await getIt<CustomerRepositoryImpl>().syncCustomers();
      
      // 3. Sincroniza Catálogo de Produtos e Serviços (PULL)
      final catalogRepo = CatalogRepositoryImpl(
        CatalogLocalDataSource(),
        CatalogRemoteDataSource()
      );
      await catalogRepo.syncCatalog();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sincronização concluída com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro na sincronização: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      await _loadAuthData(); // Atualiza contagens locais
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  Future<void> _logoutVendedor() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sair?'),
        content: const Text('Deseja encerrar a sessão do vendedor ativo?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Não', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Sim, Sair', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final authProvider = context.read<AuthProvider>();
    await authProvider.logout();
    
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthGate()),
        (route) => false,
      );
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Desconectar?'),
        content: const Text('Isso removerá a autorização do dispositivo e todos os dados offline serão apagados. Confirma?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Não', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Sim, Desconectar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final tokenManager = AuthTokenManager();
    await tokenManager.clearAll();
    
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthGate()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Perfil do Dispositivo'),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const SizedBox(height: 20),
            const CircleAvatar(
              radius: 50,
              backgroundColor: AppColors.surfaceMuted,
              child: Icon(Icons.person, size: 50, color: AppColors.primary),
            ),
            const SizedBox(height: 20),
            Text(
              _displayName,
              style: AppTypography.headingLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              _companyName,
              style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                'ID: $_deviceId',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(height: 32),
            
            // Painel de Métricas de Sincronismo
            Card(
              elevation: 0,
              color: AppColors.surfaceMuted,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Dados Locais (Offline)', style: AppTypography.bodyBold),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.people, color: AppColors.primary, size: 20),
                                  const SizedBox(width: 8),
                                  Text('Clientes', style: AppTypography.caption),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text('$_customerCount', style: AppTypography.headingMedium),
                            ],
                          ),
                        ),
                        Container(width: 1, height: 40, color: Colors.grey.shade300),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.inventory_2, color: AppColors.primary, size: 20),
                                  const SizedBox(width: 8),
                                  Text('Itens de Catálogo', style: AppTypography.caption),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text('$_catalogCount', style: AppTypography.headingMedium),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            if (_isSyncing) ...[
              const Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('Sincronizando dados com a nuvem...', style: TextStyle(color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ] else ...[
              ElevatedButton.icon(
                icon: const Icon(Icons.sync_alt),
                label: const Text('Sincronizar Tudo Agora'),
                onPressed: _syncAll,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            
            const Divider(),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: AppColors.surfaceMuted,
                child: Icon(Icons.bar_chart, color: AppColors.primary),
              ),
              title: const Text('Relatórios da Oficina'),
              subtitle: const Text('Faturamento, técnicos e mais vendidos'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ReportsPage()),
                );
              },
            ),
            const Divider(),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: AppColors.surfaceMuted,
                child: Icon(Icons.logout, color: AppColors.textSecondary),
              ),
              title: const Text('Sair / Trocar Vendedor'),
              onTap: _logoutVendedor,
            ),
            const Divider(),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: AppColors.error.withValues(alpha: 0.1),
                child: const Icon(Icons.power_settings_new, color: AppColors.error),
              ),
              title: const Text('Desconectar Dispositivo', style: TextStyle(color: AppColors.error)),
              onTap: _logout,
            ),
          ],
        ),
      ),
    );
  }
}

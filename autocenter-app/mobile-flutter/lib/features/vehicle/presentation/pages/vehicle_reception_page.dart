import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/design/app_colors.dart';
import '../../../../core/design/app_typography.dart';
import '../../../../core/design/app_spacing.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/network/auth/auth_token_manager.dart';
import '../../../vehicle/domain/entities/vehicle.dart';
import '../../../vehicle/presentation/providers/vehicle_search_provider.dart';
import '../../../service_order/presentation/pages/os_entry_checklist_page.dart';
import '../../../service_order/data/datasources/service_order_local_datasource.dart';
import 'vehicle_history_page.dart';
import '../../../../core/network/sync_queue_service.dart';
import '../../../service_order/domain/entities/service_order.dart';

class VehicleReceptionPage extends StatefulWidget {
  const VehicleReceptionPage({Key? key}) : super(key: key);

  @override
  State<VehicleReceptionPage> createState() => _VehicleReceptionPageState();
}

class _VehicleReceptionPageState extends State<VehicleReceptionPage> {
  final _plateController = TextEditingController();
  final _brandController = TextEditingController();
  final _modelController = TextEditingController();
  final _yearController = TextEditingController();

  bool _isManualMode = false;
  int _openCount = 0;
  int _inExecutionCount = 0;
  int _waitingPartsCount = 0;
  int _pendingSyncCount = 0;
  int _failedSyncCount = 0;
  bool _isSyncing = false;
  List<ServiceOrder> _recentOrders = [];

  @override
  void initState() {
    super.initState();
    _loadDashboardMetrics();
  }

  Future<void> _loadDashboardMetrics() async {
    try {
      final local = ServiceOrderLocalDataSource();
      final openList = await local.listServiceOrders(status: 'ABERTA');
      final executionList = await local.listServiceOrders(status: 'EM_EXECUCAO');
      final waitingList = await local.listServiceOrders(status: 'AGUARDANDO_PECAS');
      
      final stats = await SyncQueueService.instance.getSyncQueueStats();
      final recentList = await local.listServiceOrders();

      if (mounted) {
        setState(() {
          _openCount = openList.length;
          _inExecutionCount = executionList.length;
          _waitingPartsCount = waitingList.length;
          _pendingSyncCount = stats['pending'] ?? 0;
          _failedSyncCount = stats['failed'] ?? 0;
          _recentOrders = recentList;
        });
      }
    } catch (_) {}
  }

  Future<void> _triggerManualSync() async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Iniciando sincronização dos dados offline...')),
    );
    try {
      await SyncQueueService.instance.processQueue();
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
            content: Text('Falha na sincronização: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      await _loadDashboardMetrics();
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  Future<void> _syncSpecificOrder(String osId) async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sincronizando atendimento selecionado...')),
    );
    try {
      await SyncQueueService.instance.syncSingleServiceOrder(osId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Atendimento sincronizado com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Falha de Integração'),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'O Middleware rejeitou o envio deste atendimento com o seguinte log:',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.maxFinite,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Text(
                        e.toString(),
                        style: TextStyle(
                          color: Colors.red.shade900,
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Solução sugerida: Verifique se o cliente e o veículo estão devidamente cadastrados e se o Windows Service do Worker está rodando e conectado ao banco Firebird.',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );
      }
    } finally {
      await _loadDashboardMetrics();
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  @override
  void dispose() {
    _plateController.dispose();
    _brandController.dispose();
    _modelController.dispose();
    _yearController.dispose();
    super.dispose();
  }

  Future<void> _searchVehicle() async {
    final plate = _plateController.text.trim().toUpperCase();
    if (plate.length < 7) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Digite uma placa válida com pelo menos 7 caracteres.', style: TextStyle(color: Colors.white)),
        ),
      );
      return;
    }

    setState(() => _isManualMode = false);

    final provider = context.read<VehicleSearchProvider>();
    await provider.searchPlate(plate);
    
    // Refresh metrics on search
    _loadDashboardMetrics();

    if (mounted && provider.status == VehicleSearchStatus.error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(provider.errorMessage ?? 'Erro ao buscar veículo.')),
      );
    } else if (mounted && provider.status == VehicleSearchStatus.manualFallback) {
      setState(() => _isManualMode = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(provider.errorMessage ?? 'Preenchimento manual ativado.')),
      );
    }
  }

  void _submitManual() {
    final plate = _plateController.text.trim().toUpperCase();
    if (plate.isEmpty || plate.length < 7) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A placa é obrigatória e deve ter pelo menos 7 caracteres.', style: TextStyle(color: Colors.white)),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    final manualVehicle = Vehicle(
      plate: plate,
      brand: _brandController.text.trim().toUpperCase(),
      model: _modelController.text.trim().toUpperCase(),
      anoFabrica: int.tryParse(_yearController.text.trim()) ?? DateTime.now().year,
      anoModelo: int.tryParse(_yearController.text.trim()) ?? DateTime.now().year,
      cor: 'N/D',
      combustivel: 'FLEX',
      idCliente: 0,
      idVeiculo: 0,
    );
    context.read<VehicleSearchProvider>().saveManualVehicle(manualVehicle);
    setState(() => _isManualMode = false);
  }

  void _startChecklist(Vehicle vehicle) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OsEntryChecklistPage(vehicle: vehicle),
      ),
    );
    // Reload metrics when returning from OS creation
    _loadDashboardMetrics();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Consumer<VehicleSearchProvider>(
          builder: (context, provider, child) {
            final vehicle = provider.vehicle;
            final isLoading = provider.status == VehicleSearchStatus.loading;

            return SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: AppSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Corporate header
                  Container(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.xxl),
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(24),
                        bottomRight: Radius.circular(24),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Bom dia,', style: AppTypography.body.copyWith(color: AppColors.onPrimary.withOpacity(0.8))),
                            FutureBuilder<String?>(
                              future: getIt<AuthTokenManager>().getVendedorName(),
                              builder: (context, snapshot) {
                                final name = snapshot.data ?? 'OFICINA';
                                return Text(
                                  name.toUpperCase(),
                                  style: AppTypography.headingMedium.copyWith(
                                    color: AppColors.onPrimary,
                                    fontWeight: FontWeight.w800,
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                        Container(
                          height: 56,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                          child: Image.asset('assets/images/coliseu_logo.png', fit: BoxFit.contain, width: 140),
                        ),
                      ],
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Welcome Banner Card
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.xl),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [AppColors.primary, AppColors.primaryDark],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: const [
                              BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4)),
                            ],
                          ),
                          child: Column(
                            children: [
                              const Icon(Icons.car_rental, size: 48, color: AppColors.onPrimary),
                              const SizedBox(height: AppSpacing.sm),
                              Text(
                                'Recepção de Veículo',
                                style: AppTypography.headingMedium.copyWith(color: AppColors.onPrimary),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                'Consulte a placa para iniciar o checklist e gerar a Ordem de Serviço.',
                                style: AppTypography.body.copyWith(color: AppColors.onPrimary.withOpacity(0.8)),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: AppSpacing.md),
                        _buildDashboard(),

                        const SizedBox(height: AppSpacing.xl),

                        // Plate input & manual sync
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _plateController,
                                textCapitalization: TextCapitalization.characters,
                                maxLength: 7,
                                style: AppTypography.headingLarge,
                                textAlign: TextAlign.center,
                                decoration: const InputDecoration(
                                  hintText: 'ABC1D23',
                                  labelText: 'Placa do Veículo',
                                  counterText: '',
                                  prefixIcon: Icon(Icons.search),
                                ),
                                onSubmitted: (_) => _searchVehicle(),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.md),
                            SizedBox(
                              height: 56,
                              width: 56,
                              child: _isSyncing
                                  ? const Padding(
                                      padding: EdgeInsets.all(16.0),
                                      child: CircularProgressIndicator(strokeWidth: 3),
                                    )
                                  : ElevatedButton(
                                      onPressed: _triggerManualSync,
                                      style: ElevatedButton.styleFrom(
                                        padding: EdgeInsets.zero,
                                        backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                                        foregroundColor: AppColors.primary,
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      ),
                                      child: const Icon(Icons.sync),
                                    ),
                            ),
                          ],
                        ),

                        const SizedBox(height: AppSpacing.md),

                        if (!_isManualMode && vehicle == null)
                          ElevatedButton(
                            onPressed: isLoading ? null : _searchVehicle,
                            child: isLoading
                                ? const SizedBox(
                                    width: 24, height: 24,
                                    child: CircularProgressIndicator(color: AppColors.surface, strokeWidth: 3),
                                  )
                                : const Text('BUSCAR REGISTRO'),
                          ),

                        if (!_isManualMode && vehicle == null)
                          TextButton(
                            onPressed: () {
                              final plate = _plateController.text.trim();
                              if (plate.isEmpty || plate.length < 7) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Por favor, digite uma placa válida (mínimo 7 caracteres) antes de prosseguir.', style: TextStyle(color: Colors.white)),
                                    backgroundColor: AppColors.warning,
                                  ),
                                );
                                return;
                              }
                              setState(() => _isManualMode = true);
                            },
                            child: const Text('Preencher Ficha Manualmente'),
                          ),

                        // Contingency Form
                        if (_isManualMode) ...[
                          const SizedBox(height: AppSpacing.lg),
                          const Text(
                            'Digitação Manual de Contingência',
                            style: TextStyle(color: AppColors.warning, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          TextField(controller: _brandController, decoration: const InputDecoration(labelText: 'Marca (Ex: Fiat)')),
                          const SizedBox(height: AppSpacing.xs),
                          TextField(controller: _modelController, decoration: const InputDecoration(labelText: 'Modelo (Ex: Toro)')),
                          const SizedBox(height: AppSpacing.xs),
                          TextField(
                            controller: _yearController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Ano Fabricação (Ex: 2022)'),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          ElevatedButton(
                            onPressed: _submitManual,
                            style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: Colors.white),
                            child: const Text('CONFIRMAR FICHA RÁPIDA'),
                          ),
                          TextButton(
                            onPressed: () => setState(() => _isManualMode = false),
                            child: const Text('Cancelar'),
                          ),
                        ],

                        // Loaded Vehicle Card
                        if (vehicle != null) ...[
                          const SizedBox(height: AppSpacing.xl),
                          const Text('Ficha do Veículo', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 18)),
                          const SizedBox(height: AppSpacing.md),
                          Card(
                            elevation: 2,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpacing.md),
                              child: Column(
                                children: [
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: const CircleAvatar(
                                      backgroundColor: AppColors.surfaceMuted,
                                      child: Icon(Icons.directions_car, color: AppColors.primary),
                                    ),
                                    title: Text('${vehicle.brand} ${vehicle.model}', style: AppTypography.headingMedium),
                                    subtitle: Text('Placa: ${vehicle.plate} • Cor: ${vehicle.cor ?? 'N/D'}'),
                                    trailing: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: BorderRadius.circular(8)),
                                      child: Text(
                                        '${vehicle.anoFabrica ?? ''}',
                                        style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                                      ),
                                    ),
                                  ),
                                  const Divider(),
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: const CircleAvatar(
                                      backgroundColor: AppColors.surfaceMuted,
                                      child: Icon(Icons.person, color: AppColors.primary),
                                    ),
                                    title: Text(
                                      (vehicle.idCliente != null && vehicle.idCliente! > 0)
                                          ? "ID Cliente ERP: #${vehicle.idCliente}"
                                          : "Cliente não vinculado",
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: (vehicle.idCliente != null && vehicle.idCliente! > 0)
                                            ? AppColors.textPrimary
                                            : AppColors.warning,
                                      ),
                                    ),
                                    subtitle: Text(
                                      (vehicle.idCliente != null && vehicle.idCliente! > 0)
                                          ? 'Cliente cadastrado no banco local.'
                                          : 'Será necessário vincular um cliente na criação da OS.',
                                    ),
                                    trailing: (vehicle.idCliente != null && vehicle.idCliente! > 0)
                                        ? const Icon(Icons.check_circle, color: AppColors.success)
                                        : const Icon(Icons.warning_amber_rounded, color: AppColors.warning),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          ElevatedButton.icon(
                            onPressed: () => _startChecklist(vehicle),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.accent,
                              foregroundColor: AppColors.onAccent,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            icon: const Icon(Icons.checklist),
                            label: const Text('INICIAR CHECKLIST DE ENTRADA', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          OutlinedButton.icon(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => VehicleHistoryPage(plate: vehicle.plate!),
                                ),
                              );
                            },
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            icon: const Icon(Icons.history),
                            label: const Text('VER HISTÓRICO DE OS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          ),
                        ],

                        if (vehicle == null && !_isManualMode) ...[
                          const SizedBox(height: AppSpacing.xl),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('ÚLTIMOS ATENDIMENTOS', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
                              TextButton(
                                onPressed: _loadDashboardMetrics,
                                child: const Text('Atualizar'),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          if (_recentOrders.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 24),
                              child: Text('Nenhum atendimento recente registrado localmente.', style: TextStyle(color: AppColors.textSecondary), textAlign: TextAlign.center),
                            )
                          else
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _recentOrders.length > 5 ? 5 : _recentOrders.length,
                              separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                              itemBuilder: (context, index) {
                                final os = _recentOrders[index];
                                final isSynced = os.syncStatus == 'synced';
                                
                                return Card(
                                  margin: EdgeInsets.zero,
                                  elevation: 0,
                                  color: AppColors.surfaceMuted,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: isSynced ? Colors.green.shade50 : Colors.orange.shade50,
                                      child: Icon(
                                        isSynced ? Icons.check_circle : Icons.access_time_filled,
                                        color: isSynced ? Colors.green : Colors.orange,
                                      ),
                                    ),
                                    title: Text(os.customerName ?? 'Cliente sem nome', style: AppTypography.bodyBold),
                                    subtitle: Text('Placa: ${os.plate} • R\$ ${os.totalAmount.toStringAsFixed(2)}'),
                                    trailing: isSynced
                                        ? Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: Colors.green.shade100,
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: const Text(
                                              'Sincronizado',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.green,
                                              ),
                                            ),
                                          )
                                        : Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: Colors.orange.shade100,
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: const Text(
                                                  'Pendente',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.orange,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              IconButton(
                                                icon: const Icon(Icons.sync, color: AppColors.primary, size: 20),
                                                onPressed: () => _syncSpecificOrder(os.id),
                                                padding: EdgeInsets.zero,
                                                constraints: const BoxConstraints(),
                                                tooltip: 'Sincronizar este atendimento',
                                              ),
                                            ],
                                          ),
                                  ),
                                );
                              },
                            ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildDashboard() {
    return Column(
      children: [
        Row(
          children: [
            _buildKpiCard('Abertas', _openCount, Colors.blue),
            const SizedBox(width: AppSpacing.sm),
            _buildKpiCard('Execução', _inExecutionCount, Colors.orange),
            const SizedBox(width: AppSpacing.sm),
            _buildKpiCard('Aguard. Peças', _waitingPartsCount, Colors.purple),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            _buildKpiCard('Pendentes Sync', _pendingSyncCount, Colors.amber, icon: Icons.cloud_upload_outlined),
            const SizedBox(width: AppSpacing.sm),
            _buildKpiCard('Erros Sync', _failedSyncCount, Colors.red, icon: Icons.warning_amber_rounded),
          ],
        ),
      ],
    );
  }

  Widget _buildKpiCard(String title, int count, Color color, {IconData? icon}) {
    return Expanded(
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, color: color, size: 14),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    '$count',
                    style: AppTypography.headingMedium.copyWith(color: color, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

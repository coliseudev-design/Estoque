import 'package:flutter/material.dart';
import '../../../../core/design/app_colors.dart';
import '../../../../core/design/app_spacing.dart';
import '../../../../core/design/app_typography.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/network/sync_queue_service.dart';
import '../../domain/entities/service_order.dart';
import '../../domain/repositories/service_order_repository.dart';
import 'os_detail_page.dart';

class ActiveOrdersPage extends StatefulWidget {
  const ActiveOrdersPage({Key? key}) : super(key: key);

  @override
  State<ActiveOrdersPage> createState() => _ActiveOrdersPageState();
}

class _ActiveOrdersPageState extends State<ActiveOrdersPage> {
  final _repository = getIt<ServiceOrderRepository>();
  
  List<ServiceOrder> _orders = [];
  bool _isLoading = false;

  final List<String> _statuses = [
    'ABERTA',
    'EM_EXECUCAO',
    'AGUARDANDO_PECAS',
    'FINALIZADA',
    'ENTREGUE',
  ];

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    setState(() => _isLoading = true);
    try {
      await _repository.syncServiceOrders(); // Pull updates from remote
      final results = await _repository.listLocalServiceOrders();
      setState(() {
        _orders = results;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _refresh() async {
    await SyncQueueService.instance.processQueue();
    await _loadOrders();
  }

  List<ServiceOrder> _getOrdersByStatus(String status) {
    return _orders.where((o) => o.status.toUpperCase() == status).toList();
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'ABERTA':
        return Colors.blue;
      case 'EM_EXECUCAO':
        return Colors.orange;
      case 'AGUARDANDO_PECAS':
        return Colors.purple;
      case 'FINALIZADA':
        return Colors.green;
      case 'ENTREGUE':
        return Colors.grey;
      default:
        return Colors.black;
    }
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'ABERTA':
        return 'Aberta';
      case 'EM_EXECUCAO':
        return 'Em Execução';
      case 'AGUARDANDO_PECAS':
        return 'Aguardando Peças';
      case 'FINALIZADA':
        return 'Finalizada';
      case 'ENTREGUE':
        return 'Entregue';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Quadro de OS'),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: 'Sincronizar e Atualizar',
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _orders.isEmpty
                ? _buildEmptyState()
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _statuses.map((status) => _buildStatusColumn(status)).toList(),
                    ),
                  ),
      ),
    );
  }

  Widget _buildStatusColumn(String status) {
    final statusOrders = _getOrdersByStatus(status);
    final color = _getStatusColor(status);

    return Container(
      width: 280,
      margin: const EdgeInsets.only(right: AppSpacing.md, top: AppSpacing.md, bottom: AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Column Header
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Text(
                  _getStatusLabel(status),
                  style: AppTypography.bodyBold.copyWith(fontSize: 16),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${statusOrders.length}',
                    style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Cards list
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(AppSpacing.sm),
              itemCount: statusOrders.length,
              itemBuilder: (context, index) {
                final os = statusOrders[index];
                return _buildOrderCard(os);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderCard(ServiceOrder os) {
    final isPending = os.syncStatus == 'pending';

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          final result = await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => OsDetailPage(osId: os.id)),
          );
          if (result == true) {
            _loadOrders(); // Reload board if modified
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'OS #${os.id.length > 8 ? os.id.substring(0, 8) : os.id}',
                    style: AppTypography.bodyBold.copyWith(color: AppColors.primary),
                  ),
                  if (isPending)
                    const Icon(Icons.cloud_upload_outlined, color: AppColors.warning, size: 18)
                  else
                    const Icon(Icons.cloud_done_outlined, color: AppColors.success, size: 18),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.directions_car_outlined, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(os.plate, style: AppTypography.bodyBold),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.person_outline, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      os.customerName ?? 'Sem Cliente',
                      style: const TextStyle(fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (os.observation != null && os.observation!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  os.observation!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  Text(
                    'R\$ ${os.totalAmount.toStringAsFixed(2)}',
                    style: AppTypography.bodyBold.copyWith(color: AppColors.primary),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.assignment_outlined, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Nenhuma Ordem de Serviço cadastrada.',
            style: TextStyle(color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.lg),
          ElevatedButton.icon(
            onPressed: _refresh,
            icon: const Icon(Icons.sync),
            label: const Text('Sincronizar base'),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../../../../core/design/app_colors.dart';
import '../../../../core/design/app_spacing.dart';
import '../../../../core/design/app_typography.dart';
import '../../../service_order/data/datasources/service_order_local_datasource.dart';
import '../../../service_order/data/datasources/service_order_remote_datasource.dart';
import '../../../service_order/domain/entities/service_order.dart';
import '../../../service_order/presentation/pages/os_detail_page.dart';

class VehicleHistoryPage extends StatefulWidget {
  final String plate;

  const VehicleHistoryPage({Key? key, required this.plate}) : super(key: key);

  @override
  State<VehicleHistoryPage> createState() => _VehicleHistoryPageState();
}

class _VehicleHistoryPageState extends State<VehicleHistoryPage> {
  final _localDataSource = ServiceOrderLocalDataSource();
  final _remoteDataSource = ServiceOrderRemoteDataSource();

  List<ServiceOrder> _history = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    try {
      // 1. Fetch local cached OS
      final localList = await _localDataSource.listServiceOrders(plate: widget.plate);

      // 2. Fetch remote middleware OS for this plate
      List<ServiceOrder> remoteList = [];
      try {
        remoteList = await _remoteDataSource.getServiceOrders(plate: widget.plate);
      } catch (e) {
        print('[VehicleHistoryPage] Falha ao buscar OS remotas: $e');
      }

      // 3. Merge lists by ID (prioritize local pending over remote)
      final Map<String, ServiceOrder> merged = {};
      for (var os in localList) {
        merged[os.id] = os;
      }
      for (var os in remoteList) {
        if (merged.containsKey(os.id)) {
          if (merged[os.id]!.syncStatus == 'synced') {
            merged[os.id] = os;
          }
        } else {
          merged[os.id] = os;
        }
      }

      final sorted = merged.values.toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      setState(() {
        _history = sorted;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao carregar histórico: $e')),
      );
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toUpperCase()) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text('Histórico Placa ${widget.plate}'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _history.isEmpty
                ? _buildEmptyState()
                : RefreshIndicator(
                    onRefresh: _loadHistory,
                    child: ListView.builder(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      itemCount: _history.length,
                      itemBuilder: (context, index) {
                        final os = _history[index];
                        final isPending = os.syncStatus == 'pending';
                        final shortId = os.id.length > 8 ? os.id.substring(0, 8) : os.id;
                        final dateStr = os.createdAt.replaceAll('T', ' ').substring(0, 16);

                        return Card(
                          margin: const EdgeInsets.only(bottom: AppSpacing.md),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 1,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () async {
                              final modified = await Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => OsDetailPage(osId: os.id)),
                              );
                              if (modified == true) {
                                _loadHistory();
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
                                        'OS #$shortId',
                                        style: AppTypography.bodyBold.copyWith(color: AppColors.primary),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: _getStatusColor(os.status).withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          os.status,
                                          style: TextStyle(
                                            color: _getStatusColor(os.status),
                                            fontWeight: FontWeight.bold,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: AppSpacing.sm),
                                  Text(
                                    'Abertura: $dateStr',
                                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                  ),
                                  if (os.customerName != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      'Cliente: ${os.customerName}',
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ],
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
                                      Row(
                                        children: [
                                          Icon(
                                            isPending ? Icons.cloud_upload_outlined : Icons.cloud_done_outlined,
                                            color: isPending ? AppColors.warning : AppColors.success,
                                            size: 16,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            isPending ? 'Pendente' : 'Sincronizado',
                                            style: TextStyle(
                                              color: isPending ? AppColors.warning : AppColors.success,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
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
                      },
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
          Icon(Icons.history, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Nenhuma Ordem de Serviço encontrada para a placa ${widget.plate}.',
            style: TextStyle(color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

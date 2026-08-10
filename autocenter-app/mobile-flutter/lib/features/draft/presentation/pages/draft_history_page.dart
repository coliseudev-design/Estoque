import 'package:flutter/material.dart';
import '../../data/datasources/draft_remote_datasource.dart';
import '../../data/datasources/draft_local_datasource.dart';
import '../../domain/entities/draft.dart';
import '../../../../core/database/database_helper.dart';
import '../../../../core/printing/ticket_share_service.dart';
import '../../../../core/network/sync_service.dart';

class DraftHistoryPage extends StatefulWidget {
  const DraftHistoryPage({Key? key}) : super(key: key);

  @override
  State<DraftHistoryPage> createState() => _DraftHistoryPageState();
}

class _DraftHistoryPageState extends State<DraftHistoryPage> {
  final DraftRemoteDataSource _remoteDataSource = DraftRemoteDataSource();
  final DraftLocalDataSource _localDataSource = DraftLocalDataSource(dbHelper: DatabaseHelper.instance);
  final TicketShareService _shareService = TicketShareService();
  
  List<Map<String, dynamic>> _history = [];
  List<Draft> _localDrafts = [];
  bool _isLoading = true;
  int _selectedTab = 0; // 0 = Nuvem, 1 = Fila Local

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchData();
    });
  }

  void _fetchData() {
    if (_selectedTab == 0) {
      _fetchHistory();
    } else {
      _fetchLocalDrafts();
    }
  }

  Future<void> _fetchHistory() async {
    setState(() => _isLoading = true);
    final data = await _remoteDataSource.getHistory();
    if (mounted) {
      setState(() {
        _history = data;
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchLocalDrafts() async {
    setState(() => _isLoading = true);
    try {
      final data = await _localDataSource.getPendingDrafts();
      if (mounted) {
        setState(() {
          _localDrafts = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao buscar fila local: $e')),
        );
      }
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toUpperCase()) {
      case 'DRAFT': return Colors.grey;
      case 'APPROVED': return Colors.orange;
      case 'INTEGRATED': return Colors.green;
      case 'CANCELADO': return Colors.red;
      case 'PENDENTE_SYNC': return Colors.blue;
      default: return Colors.blueGrey;
    }
  }

  Future<void> _shareQuote(Map<String, dynamic> item) async {
    try {
      await _shareService.shareQuoteTicket(
        plate: item['plate'] ?? 'N/A',
        customerName: item['customer_name'] ?? 'Balcão',
        items: [], // MVP (em produção pode puxar listagem)
        totalAmount: double.tryParse(item['total_amount']?.toString() ?? '0') ?? 0.0,
        status: item['status'] ?? 'N/A',
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao compartilhar: $e')));
    }
  }

  void _triggerSync() {
    SyncService.registerOfflineSync();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Solicitação de sincronização de rascunhos iniciada...'),
        backgroundColor: Colors.green,
      ),
    );
    // Recarrega os dados locais após alguns instantes
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && _selectedTab == 1) {
        _fetchLocalDrafts();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: const Text('Histórico de Vistorias', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF0F3A70),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_selectedTab == 1)
            IconButton(
              icon: const Icon(Icons.sync_outlined),
              tooltip: 'Sincronizar Fila',
              onPressed: _triggerSync,
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchData,
          )
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment<int>(
                  value: 0,
                  icon: Icon(Icons.cloud_outlined),
                  label: Text('Nuvem (Salvos)'),
                ),
                ButtonSegment<int>(
                  value: 1,
                  icon: Icon(Icons.phonelink_ring_outlined),
                  label: Text('Fila Local (Pendente)'),
                ),
              ],
              selected: {_selectedTab},
              onSelectionChanged: (Set<int> newSelection) {
                setState(() {
                  _selectedTab = newSelection.first;
                });
                _fetchData();
              },
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFFF26822)))
                : _selectedTab == 0
                    ? _buildCloudHistoryList()
                    : _buildLocalDraftsList(),
          ),
        ],
      ),
    );
  }

  Widget _buildCloudHistoryList() {
    if (_history.isEmpty) {
      return const Center(child: Text('Nenhuma vistoria encontrada na nuvem.', style: TextStyle(fontSize: 16)));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _history.length,
      itemBuilder: (context, index) {
        final item = _history[index];
        final status = item['status'] ?? 'UNKNOWN';

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 2,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: CircleAvatar(
              backgroundColor: _getStatusColor(status).withOpacity(0.2),
              child: Icon(Icons.directions_car, color: _getStatusColor(status)),
            ),
            title: Text(item['plate'] ?? 'SEM-PLACA', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text('Cliente: ${item["customer_name"] ?? "Balcão"}'),
                const SizedBox(height: 4),
                Builder(
                  builder: (context) {
                    final dateStr = item["created_at"]?.toString() ?? "";
                    final displayDate = dateStr.length >= 10 ? dateStr.substring(0, 10) : dateStr;
                    return Text('Data: ${displayDate.isNotEmpty ? displayDate : "-"}');
                  },
                ),
              ],
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('R\$ ${item["total_amount"]}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getStatusColor(status),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    status,
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () => _shareQuote(item),
                  child: const Icon(Icons.share, color: Color(0xFF0F3A70)),
                )
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLocalDraftsList() {
    if (_localDrafts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.cloud_done_outlined, size: 64, color: Colors.green),
              SizedBox(height: 16),
              Text(
                'Tudo sincronizado!',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'Não há orçamentos pendentes de sincronização.',
                style: TextStyle(color: Colors.grey, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _localDrafts.length,
      itemBuilder: (context, index) {
        final item = _localDrafts[index];
        final status = item.status ?? 'PENDENTE_SYNC';

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 2,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: CircleAvatar(
              backgroundColor: _getStatusColor(status).withOpacity(0.2),
              child: Icon(Icons.cloud_queue_outlined, color: _getStatusColor(status)),
            ),
            title: Text(item.vehiclePlate ?? 'SEM-PLACA', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text('Cliente: ${item.customerName ?? "Balcão"}'),
                const SizedBox(height: 4),
                Text('Data: ${item.createdAt?.substring(0, 10) ?? "-"}'),
              ],
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getStatusColor(status),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'PENDENTE',
                    style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: _triggerSync,
                  child: const Icon(Icons.sync, color: Color(0xFFF26822)),
                )
              ],
            ),
          ),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import '../../../../core/design/app_colors.dart';
import '../../../../core/design/app_spacing.dart';
import '../../../../core/design/app_typography.dart';
import '../../../../core/database/database_helper.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({Key? key}) : super(key: key);

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  List<Map<String, dynamic>> _faturamentoDia = [];
  List<Map<String, dynamic>> _faturamentoMes = [];
  List<Map<String, dynamic>> _tecnicosKpi = [];
  List<Map<String, dynamic>> _topItens = [];
  
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadReportsData();
  }

  Future<void> _loadReportsData() async {
    setState(() => _isLoading = true);
    try {
      final db = await _dbHelper.database;

      // 1. Faturamento por Dia (últimos 30 dias com vendas)
      final diaRes = await db.rawQuery('''
        SELECT SUBSTR(created_at, 1, 10) AS label, SUM(total_amount) AS total 
        FROM service_orders 
        GROUP BY label 
        ORDER BY label DESC 
        LIMIT 30
      ''');

      // 2. Faturamento por Mês (últimos 12 meses com vendas)
      final mesRes = await db.rawQuery('''
        SELECT SUBSTR(created_at, 1, 7) AS label, SUM(total_amount) AS total 
        FROM service_orders 
        GROUP BY label 
        ORDER BY label DESC 
        LIMIT 12
      ''');

      // 3. Qtd de OS por Técnico
      final techRes = await db.rawQuery('''
        SELECT t.name AS label, COUNT(DISTINCT item.service_order_id) AS total
        FROM service_order_items item 
        JOIN technicians t ON item.technician_id = t.id 
        GROUP BY label 
        ORDER BY total DESC
      ''');

      // 4. Top 10 Itens Mais Vendidos (peças e serviços)
      final itensRes = await db.rawQuery('''
        SELECT product_description AS label, SUM(quantity) AS total
        FROM service_order_items 
        GROUP BY label 
        ORDER BY total DESC 
        LIMIT 10
      ''');

      setState(() {
        _faturamentoDia = diaRes;
        _faturamentoMes = mesRes;
        _tecnicosKpi = techRes;
        _topItens = itensRes;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao carregar relatórios: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          title: const Text('Relatórios da Oficina'),
          centerTitle: true,
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Faturamento', icon: Icon(Icons.monetization_on_outlined)),
              Tab(text: 'Técnicos', icon: Icon(Icons.people_outline)),
              Tab(text: 'Mais Vendidos', icon: Icon(Icons.star_outline)),
            ],
          ),
        ),
        body: SafeArea(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(
                  children: [
                    _buildFaturamentoTab(),
                    _buildTecnicosTab(),
                    _buildItensTab(),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildFaturamentoTab() {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Text('Faturamento por Mês', style: AppTypography.headingMedium),
        const SizedBox(height: AppSpacing.sm),
        if (_faturamentoMes.isEmpty)
          const Text('Nenhum dado mensal registrado.')
        else
          Card(
            elevation: 1,
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _faturamentoMes.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final row = _faturamentoMes[index];
                final double val = (row['total'] as num).toDouble();
                return ListTile(
                  title: Text('Mês: ${row['label']}', style: AppTypography.bodyBold),
                  trailing: Text(
                    'R\$ ${val.toStringAsFixed(2)}',
                    style: AppTypography.bodyBold.copyWith(color: AppColors.primary),
                  ),
                );
              },
            ),
          ),
        const SizedBox(height: AppSpacing.xl),
        Text('Faturamento por Dia (Últimos 30 dias)', style: AppTypography.headingMedium),
        const SizedBox(height: AppSpacing.sm),
        if (_faturamentoDia.isEmpty)
          const Text('Nenhum dado diário registrado.')
        else
          Card(
            elevation: 1,
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _faturamentoDia.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final row = _faturamentoDia[index];
                final double val = (row['total'] as num).toDouble();
                return ListTile(
                  title: Text('Dia: ${row['label']}'),
                  trailing: Text(
                    'R\$ ${val.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildTecnicosTab() {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Text('Ordens de Serviço por Técnico', style: AppTypography.headingMedium),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Quantidade de Ordens de Serviço distintas em que o técnico executou pelo menos um serviço.',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
        ),
        const SizedBox(height: AppSpacing.md),
        if (_tecnicosKpi.isEmpty)
          _buildEmptyState('Nenhuma atribuição de técnicos registrada.')
        else
          Card(
            elevation: 1,
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _tecnicosKpi.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final row = _tecnicosKpi[index];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.blue.withValues(alpha: 0.1),
                    child: Text('${index + 1}', style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                  ),
                  title: Text(row['label'] as String, style: AppTypography.bodyBold),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(10)),
                    child: Text(
                      '${row['total']} OSs',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildItensTab() {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Text('Top 10 Itens Mais Vendidos', style: AppTypography.headingMedium),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Quantidade acumulada de peças e serviços faturados.',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
        ),
        const SizedBox(height: AppSpacing.md),
        if (_topItens.isEmpty)
          _buildEmptyState('Nenhum item vendido registrado.')
        else
          Card(
            elevation: 1,
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _topItens.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final row = _topItens[index];
                final qty = (row['total'] as num).toDouble();
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.orange.withValues(alpha: 0.1),
                    child: const Icon(Icons.star, color: Colors.orange, size: 20),
                  ),
                  title: Text(row['label'] as String, style: AppTypography.bodyBold),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(10)),
                    child: Text(
                      'Qtd: ${qty.toStringAsFixed(0)}',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildEmptyState(String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            Icon(Icons.bar_chart, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: AppSpacing.md),
            Text(
              text,
              style: TextStyle(color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

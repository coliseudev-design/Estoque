import 'package:flutter/material.dart';
import '../../../../core/design/app_colors.dart';
import '../../../../core/design/app_typography.dart';
import '../../../../core/design/app_spacing.dart';
import '../../data/datasources/catalog_local_datasource.dart';
import '../../data/datasources/catalog_remote_datasource.dart';
import '../../data/repositories/catalog_repository_impl.dart';
import '../../data/models/catalog_item_model.dart';
import 'package:shimmer/shimmer.dart';

class ServicesCatalogPage extends StatefulWidget {
  const ServicesCatalogPage({Key? key}) : super(key: key);

  @override
  State<ServicesCatalogPage> createState() => _ServicesCatalogPageState();
}

class _ServicesCatalogPageState extends State<ServicesCatalogPage> with SingleTickerProviderStateMixin {
  late CatalogRepositoryImpl _repository;
  TabController? _tabController;
  
  List<String> _categories = [];
  Map<String, List<CatalogItemModel>> _catalogData = {};
  bool _isLoading = true;
  int _totalCount = 0;

  @override
  void initState() {
    super.initState();
    _repository = CatalogRepositoryImpl(
      CatalogLocalDataSource(),
      CatalogRemoteDataSource()
    );
    _loadCatalog();
  }

  Future<void> _loadCatalog() async {
    try {
      final categories = await _repository.getCategories();
      final total = await _repository.getCatalogCount();
      
      // Fallback em caso de banco vazio para não quebrar a UI
      final effectiveCategories = categories.isEmpty ? ['Geral'] : categories;
      
      Map<String, List<CatalogItemModel>> data = {};
      for (final cat in effectiveCategories) {
        data[cat] = await _repository.getCatalogByCategory(cat);
      }

      if (mounted) {
        setState(() {
          _categories = effectiveCategories;
          _catalogData = data;
          _totalCount = total;
          _tabController = TabController(length: _categories.length, vsync: this);
          _isLoading = false;
        });
      }
    } catch (e) {
      print("Erro ao carregar catálogo: \$e");
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _tabController == null) {
      return Scaffold(
        appBar: AppBar(title: Text('Tabela de Serviços/Peças ($_totalCount)')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Tabela de Serviços/Peças ($_totalCount)'),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            onPressed: () async {
              setState(() => _isLoading = true);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Sincronizando catálogo...')),
              );
              try {
                await _repository.syncCatalog();
                await _loadCatalog();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Catálogo atualizado!')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Erro: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              } finally {
                if (mounted) {
                  setState(() => _isLoading = false);
                }
              }
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textTertiary,
          indicatorColor: AppColors.primary,
          isScrollable: _categories.length > 3,
          tabs: _categories.map((c) => Tab(text: c)).toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _categories.map((cat) => _buildList(cat)).toList(),
      ),
    );
  }

  Widget _buildList(String category) {
    final items = _catalogData[category] ?? [];
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined, size: 64, color: AppColors.textTertiary.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            const Text('Nenhum item sincronizado.', style: TextStyle(color: AppColors.textTertiary)),
          ],
        )
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final codeText = item.code != null ? ' • Cód: ${item.code}' : '';
        return Card(
          margin: const EdgeInsets.only(bottom: AppSpacing.md),
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: AppColors.surfaceMuted,
              child: Icon(Icons.build_circle, color: AppColors.primary),
            ),
            title: Text(item.name, style: AppTypography.bodyBold),
            subtitle: Text('ID ERP: ${item.erpId}$codeText', style: AppTypography.caption),
            trailing: Text(
              'R\$ ${item.price.toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.success),
            ),
          ),
        );
      },
    );
  }
}

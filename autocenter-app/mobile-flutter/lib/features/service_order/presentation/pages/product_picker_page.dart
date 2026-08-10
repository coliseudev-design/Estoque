import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/design/app_colors.dart';
import '../../../../core/design/app_spacing.dart';
import '../../../../core/design/app_typography.dart';
import '../../../services/data/datasources/catalog_local_datasource.dart';
import '../../../services/data/models/catalog_item_model.dart';

class ProductPickerPage extends StatefulWidget {
  const ProductPickerPage({Key? key}) : super(key: key);

  @override
  State<ProductPickerPage> createState() => _ProductPickerPageState();
}

class _ProductPickerPageState extends State<ProductPickerPage> {
  final _searchController = TextEditingController();
  final _localDataSource = CatalogLocalDataSource();

  List<CatalogItemModel> _items = [];
  bool _isLoading = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadInitialItems();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadInitialItems() async {
    setState(() => _isLoading = true);
    final results = await _localDataSource.getAllCatalog();
    setState(() {
      _items = results;
      _isLoading = false;
    });
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    _debounce = Timer(const Duration(milliseconds: 300), () async {
      setState(() => _isLoading = true);
      if (query.trim().isEmpty) {
        final results = await _localDataSource.getAllCatalog();
        setState(() {
          _items = results;
          _isLoading = false;
        });
      } else {
        final results = await _localDataSource.searchCatalog(query.trim());
        setState(() {
          _items = results;
          _isLoading = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Selecionar Item'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            children: [
              TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'Buscar por Descrição ou Código...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            _loadInitialItems();
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _items.isEmpty
                        ? _buildEmptyState()
                        : ListView.separated(
                            itemCount: _items.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final item = _items[index];
                              final isService = item.category.toLowerCase().contains('serviço') ||
                                  item.category.toLowerCase().contains('mao de obra');

                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: isService
                                      ? Colors.orange.withValues(alpha: 0.15)
                                      : Colors.blue.withValues(alpha: 0.15),
                                  child: Icon(
                                    isService ? Icons.build_outlined : Icons.settings_suggest_outlined,
                                    color: isService ? Colors.orange : Colors.blue,
                                  ),
                                ),
                                title: Text(
                                  item.name,
                                  style: AppTypography.bodyBold,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Código: ${item.code ?? 'N/D'} • Cat: ${item.category}'),
                                  ],
                                ),
                                trailing: Text(
                                  'R\$ ${item.price.toStringAsFixed(2)}',
                                  style: AppTypography.bodyBold.copyWith(color: AppColors.primary),
                                ),
                                onTap: () {
                                  Navigator.of(context).pop(item);
                                },
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.category_outlined, size: 64, color: Colors.grey.shade300),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Nenhum item encontrado no catálogo.',
          style: TextStyle(color: Colors.grey.shade600),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

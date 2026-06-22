/// CatalogScreen — Catálogo de produtos com busca e filtro por campo.
///
/// UX FIELD RULES:
/// - Busca com debounce de 300ms (não dispara a cada tecla)
/// - Lista virtualizada — sem travamento com 5000+ itens
/// - Produto sem estoque: badge "Sem Estoque"
/// - Código sempre visível (vendedores buscam por código, não nome)
/// - Dropdown de campo de busca: Todos, Descrição, Código, Referência, Cód. Barras, Marca
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_typography.dart';
import '../../core/network/auto_sync_service.dart';
import '../../core/network/connectivity_service.dart';
import '../../core/repositories/models/models.dart';
import '../../core/repositories/product_repository.dart';
import '../../core/services/favorite_service.dart';
import '../../core/config/app_config_service.dart';
import '../../shared/coliseu_product_card.dart';

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key});

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  final ProductRepository  _repo         = GetIt.I<ProductRepository>();
  final AutoSyncService    _autoSync      = GetIt.I<AutoSyncService>();
  final ConnectivityService _connectivity = GetIt.I<ConnectivityService>();
  final FavoriteService      _favService   = GetIt.I<FavoriteService>();
  final TextEditingController _searchCtrl = TextEditingController();
  final _currencyFmt = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');

  List<Product> _products  = [];
  Set<String>   _favorites = {};
  int?          _branchDeptoId;
  bool _loading             = true;
  bool _syncing             = false;
  String _searchQuery       = '';
  Timer? _debounce;
  SearchField? _searchField;

  @override
  void initState() {
    super.initState();
    _loadBranchConfig();
    _loadProducts('');
    _loadFavorites();
    _autoSync.stateNotifier.addListener(_onSyncChanged);
  }

  void _onSyncChanged() {
    final s = _autoSync.stateNotifier.value;
    if (s == AutoSyncState.success || s == AutoSyncState.partial) {
      _loadProducts(_searchQuery);
    }
  }

  Future<void> _loadBranchConfig() async {
    final config = AppConfigService();
    final depto = await config.getBranchErpDeptoPadrao();
    if (mounted) setState(() => _branchDeptoId = depto);
  }

  Future<void> _loadFavorites() async {
    final codes = await _favService.allCodes();
    if (mounted) setState(() => _favorites = codes);
  }

  @override
  void dispose() {
    _autoSync.stateNotifier.removeListener(_onSyncChanged);
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (query != _searchQuery) {
        _searchQuery = query;
        _loadProducts(query);
      }
    });
  }

  Future<void> _loadProducts(String query) async {
    setState(() => _loading = true);
    final results = await _repo.search(query, searchField: _searchField, limit: 5000);
    if (!mounted) return;
    setState(() { _products = results; _loading = false; });
  }

  void _selectSearchField(SearchField? field) {
    if (_searchField == field) return;
    setState(() => _searchField = field);
    _loadProducts(_searchQuery);
  }

  void _openBarcodeScanner() {
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.black,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SizedBox(
        height: 360,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(children: [
                const Icon(Icons.qr_code_scanner_rounded, color: Colors.white),
                const SizedBox(width: 8),
                const Expanded(child: Text('Aponte para o código de barras', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600))),
                IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.of(context).pop()),
              ]),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                child: MobileScanner(
                  onDetect: (capture) {
                    final code = capture.barcodes.first.rawValue;
                    if (code != null && code.isNotEmpty) {
                      Navigator.of(context).pop();
                      setState(() => _searchField = SearchField.barCode);
                      _searchCtrl.text = code;
                      _onSearchChanged(code);
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Search bar
        Container(
          color: AppColors.surfacePrimary,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              _SearchFieldDropdown(selected: _searchField, onChanged: _selectSearchField),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _searchCtrl, onChanged: _onSearchChanged,
                  style: AppTypography.body,
                  decoration: InputDecoration(
                    hintText: _searchField == null ? 'Buscar por nome, código, ref...' : 'Buscar por ${_searchField!.label.toLowerCase()}...',
                    prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(icon: const Icon(Icons.clear, size: 20), onPressed: () { _searchCtrl.clear(); _onSearchChanged(''); })
                        : IconButton(icon: const Icon(Icons.qr_code_scanner_rounded, color: AppColors.textSecondary), tooltip: 'Scan código de barras', onPressed: _openBarcodeScanner),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Resultado counter
        if (!_loading)
          Container(
            width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: AppColors.surfaceSecondary,
            child: Text(
              _products.isEmpty ? 'Nenhum produto encontrado' : '${_products.length} produto${_products.length != 1 ? 's' : ''}',
              style: AppTypography.badge.copyWith(color: AppColors.textSecondary),
            ),
          ),

        // Lista
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _products.isEmpty ? _buildEmptyState()
              : ListView.builder(
                  itemCount: _products.length, itemExtent: 112, padding: const EdgeInsets.only(top: 8),
                  itemBuilder: (ctx, i) {
                    final p = _products[i];
                    final isLocalBranch = _branchDeptoId != null && p.erpDeptoPadrao == _branchDeptoId;
                    
                    return ColiseuProductCard(
                      code: p.code, name: p.name, price: p.price, stock: p.stock,
                      brand: p.brand, category: p.category, reference: p.reference, unit: p.unit,
                      isLocalBranch: isLocalBranch,
                      isFavorite: _favorites.contains(p.code),
                      onFavorite: () async {
                        final added = await _favService.toggle(p.code);
                        setState(() {
                          if (added) { _favorites.add(p.code); }
                          else       { _favorites.remove(p.code); }
                        });
                      },
                      onTap: () => _showProductDetail(p),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _showProductDetail(Product p) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16), decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)))),
              Text(p.name, style: AppTypography.headingLarge),
              const SizedBox(height: 12),
              _detailRow('Código', p.code),
              _detailRow('Preço', _currencyFmt.format(p.price)),
              if (p.priceMin != null && p.priceMin! > 0) _detailRow('Preço Mín.', _currencyFmt.format(p.priceMin!)),
              _detailRow('Estoque', '${p.stock.toStringAsFixed(0)} ${p.unit ?? 'un'}'),
              if (p.category != null && p.category!.isNotEmpty) _detailRow('Categoria', p.category!),
              if (p.brand != null && p.brand!.isNotEmpty) _detailRow('Marca', p.brand!),
              if (p.reference != null && p.reference!.isNotEmpty) _detailRow('Referência', p.reference!),
              if (p.barCode != null && p.barCode!.isNotEmpty) _detailRow('Cód. Barras', p.barCode!),
              if (p.maxDiscount != null && p.maxDiscount! > 0) _detailRow('Desc. Máx.', '${p.maxDiscount!.toStringAsFixed(1)}%'),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(width: 100, child: Text(label, style: AppTypography.caption.copyWith(color: AppColors.textSecondary))),
        Expanded(child: Text(value, style: AppTypography.body.copyWith(fontWeight: FontWeight.w500))),
      ]),
    );
  }

  Widget _buildEmptyState() {
    final isEmptyCatalog = _searchQuery.isEmpty && _searchField == null;
    final isOffline = _connectivity.currentStatus == ConnectivityStatus.offline;

    if (isEmptyCatalog) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(isOffline ? Icons.cloud_off_rounded : Icons.inventory_2_outlined, size: 64, color: AppColors.textTertiary),
              const SizedBox(height: 16),
              Text(isOffline ? 'Sem catálogo offline' : 'Catálogo vazio', style: AppTypography.cardTitle.copyWith(color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              Text(isOffline ? 'Verifique sua conexão e faça a sincronização inicial.' : 'Conecte-se e sincronize para carregar os produtos.',
                textAlign: TextAlign.center, style: AppTypography.body.copyWith(color: AppColors.textTertiary)),
              const SizedBox(height: 12),
              if (!isOffline)
                Text('Use o botão Sincronizar em Início ou Perfil.',
                  textAlign: TextAlign.center, style: AppTypography.caption.copyWith(color: AppColors.textTertiary)),
              if (isOffline)
                OutlinedButton.icon(icon: const Icon(Icons.wifi_off_rounded), label: const Text('Sem conexão'), onPressed: null,
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.textTertiary)),
            ],
          ),
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.search_off_rounded, size: 56, color: AppColors.textTertiary),
          const SizedBox(height: 16),
          Text('Nenhum produto encontrado', style: AppTypography.body.copyWith(color: AppColors.textSecondary)),
          if (_searchQuery.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('para "$_searchQuery"', style: AppTypography.badge.copyWith(color: AppColors.textTertiary)),
          ],
          const SizedBox(height: 24),
          TextButton.icon(icon: const Icon(Icons.clear), label: const Text('Limpar filtros'),
            onPressed: () { _searchCtrl.clear(); setState(() => _searchField = null); _onSearchChanged(''); }),
        ],
      ),
    );
  }

  Future<void> _syncNow() async {
    setState(() => _syncing = true);
    try {
      await _autoSync.triggerManual();
      await _loadProducts(_searchQuery);
      if (mounted && _products.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${_products.length} produtos carregados!', style: const TextStyle(color: Colors.white)),
          backgroundColor: AppColors.syncSuccess, duration: const Duration(seconds: 3), behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
class _SearchFieldDropdown extends StatelessWidget {
  final SearchField? selected;
  final ValueChanged<SearchField?> onChanged;
  const _SearchFieldDropdown({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final label = selected?.label ?? 'Todos';
    return Material(
      color: selected != null ? AppColors.actionPrimary.withOpacity(0.1) : AppColors.surfaceSecondary,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _showPicker(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.filter_list_rounded, size: 16, color: selected != null ? AppColors.actionPrimary : AppColors.textSecondary),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: selected != null ? AppColors.actionPrimary : AppColors.textSecondary)),
            const SizedBox(width: 2),
            Icon(Icons.expand_more_rounded, size: 16, color: selected != null ? AppColors.actionPrimary : AppColors.textSecondary),
          ]),
        ),
      ),
    );
  }

  void _showPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(children: [
              const Icon(Icons.filter_list_rounded, size: 20), const SizedBox(width: 8),
              Text('Buscar por...', style: AppTypography.cardTitle),
            ]),
          ),
          const Divider(height: 1),
          _opt(ctx, label: 'Todos os campos', value: null),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ...SearchField.values.map((f) => _opt(ctx, label: f.label, value: f)),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Widget _opt(BuildContext context, {required String label, required SearchField? value}) {
    final sel = selected == value;
    return ListTile(
      dense: true,
      leading: Icon(sel ? Icons.radio_button_checked : Icons.radio_button_off,
        color: sel ? AppColors.actionPrimary : AppColors.textTertiary, size: 20),
      title: Text(label, style: TextStyle(fontWeight: sel ? FontWeight.w600 : FontWeight.w400, color: sel ? AppColors.actionPrimary : AppColors.textPrimary)),
      onTap: () { Navigator.of(context).pop(); onChanged(value); },
    );
  }
}

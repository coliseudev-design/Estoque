/// ProductPickerScreen — Catálogo para adicionar produtos ao pedido.
///
/// Padrão de layout baseado no app de referência:
/// - Filtro por categoria (chips)
/// - Busca por nome/código
/// - Produtos com checkbox de seleção
/// - Quando selecionado: exibe controles inline (qty, preço, desconto)
/// - Botão "Adicionar item" confirma a adição ao carrinho
library;

import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../core/cart/cart_notifier.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_typography.dart';
import '../../core/design/app_spacing.dart';
import '../../core/repositories/models/models.dart';
import '../../core/repositories/product_repository.dart';
import '../../core/services/customer_service.dart';
import '../../core/services/price_service.dart';

class ProductPickerScreen extends StatefulWidget {
  final CartNotifier cart;
  final String? customerId;

  const ProductPickerScreen({super.key, required this.cart, this.customerId});

  @override
  State<ProductPickerScreen> createState() => _ProductPickerScreenState();
}

class _ProductPickerScreenState extends State<ProductPickerScreen> {
  final ProductRepository _repo = GetIt.I<ProductRepository>();
  final TextEditingController _searchCtrl = TextEditingController();
  final _currencyFmt = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  List<Product> _products = [];
  bool _loading = true;
  String _searchQuery = '';
  Timer? _debounce;
  Map<String, double> _resolvedPrices = {};
  bool _onlyInStock = false;

  /// Campo de busca selecionado (null = busca em todos os campos).
  SearchField? _searchField;

  // Produto selecionado (expandido com controles inline)
  String? _selectedCode;
  final Map<String, TextEditingController> _qtyControllers = {};
  final Map<String, TextEditingController> _priceControllers = {};
  final Map<String, FocusNode> _priceFocusNodes = {};
  final Map<String, TextEditingController> _discountPctControllers = {};
  final Map<String, TextEditingController> _discountValControllers = {};
  final Map<String, double> _quantities = {};

  // ── Sugestões do cliente ──────────────────────────────────────────────────
  List<Map<String, dynamic>> _suggestions = [];
  bool _loadingSuggestions = false;

  // ── Scanner PDV ──────────────────────────────────────────────────────────
  bool _scannerMode = false;
  bool _scanCooldown = false;
  int  _scanCount = 0;
  bool _scanFlash = false;
  MobileScannerController? _scannerCtrl;
  final AudioPlayer _beepPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _loadProducts('');
    _loadSuggestions();
    // Pré-carrega o beep para resposta instantânea
    _beepPlayer.setSource(AssetSource('audio/beep.wav'));
  }

  Future<void> _loadSuggestions() async {
    final cid = widget.customerId;
    if (cid == null || cid.isEmpty) return;
    setState(() => _loadingSuggestions = true);
    try {
      final svc = GetIt.I<CustomerService>();
      final top = await svc.topProducts(cid, limit: 5);
      if (mounted) setState(() { _suggestions = top; _loadingSuggestions = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingSuggestions = false);
    }
  }

  // ── Scanner PDV: toggle & handler ──────────────────────────────────────

  void _toggleScanner() {
    setState(() {
      _scannerMode = !_scannerMode;
      if (_scannerMode) {
        _scannerCtrl = MobileScannerController();
        _scanCount = 0;
      } else {
        _scannerCtrl?.dispose();
        _scannerCtrl = null;
      }
    });
  }

  Future<void> _onBarcodeDetected(BarcodeCapture capture) async {
    if (_scanCooldown) return;
    final code = capture.barcodes.first.rawValue;
    if (code == null || code.isEmpty) return;

    // Cooldown para evitar leitura duplicada
    _scanCooldown = true;

    final product = await _repo.findByBarcode(code);

    if (!mounted) return;

    if (product == null) {
      // Produto não encontrado
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Produto não encontrado: $code'),
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else if (!product.isInStock && !widget.cart.canSellWithoutStock) {
      // Sem estoque e a empresa não permite venda negativa
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${product.name} — sem estoque'),
          backgroundColor: AppColors.warning,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      // Sucesso — adiciona ao carrinho (produto em estoque, ou estoque negativo liberado)
      if (!product.isInStock) {
        // Aviso quando liberado mas sem estoque
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${product.name} — sem estoque (venda liberada)'),
            backgroundColor: AppColors.warning,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      await widget.cart.addProduct(product, quantity: 1);
      _scanCount++;

      // Beep + vibração
      _beepPlayer.stop();
      _beepPlayer.play(AssetSource('audio/beep.wav'));
      HapticFeedback.mediumImpact();

      // Flash verde visual
      setState(() => _scanFlash = true);
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) setState(() => _scanFlash = false);
      });

      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${product.name} adicionado',
                style: const TextStyle(color: Colors.white),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ]),
          backgroundColor: AppColors.success,
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    // Libera cooldown após 1.5s
    await Future.delayed(const Duration(milliseconds: 1500));
    _scanCooldown = false;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _scannerCtrl?.dispose();
    _beepPlayer.dispose();
    for (final c in _qtyControllers.values) {
      c.dispose();
    }
    for (final c in _priceControllers.values) {
      c.dispose();
    }
    for (final f in _priceFocusNodes.values) {
      f.dispose();
    }
    for (final c in _discountPctControllers.values) {
      c.dispose();
    }
    for (final c in _discountValControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Data Loading ──────────────────────────────────────────────────────────

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
    final results = await _repo.search(
      query,
      searchField: _searchField,
      limit: 200,
    );
    
    final priceSvc = PriceService();
    final resolved = await priceSvc.resolvePrices(
      products: results,
      priceTableId: widget.cart.priceTableId,
    );

    if (!mounted) return;
    setState(() {
      _products = results;
      _resolvedPrices = resolved;
      _loading = false;
    });
  }

  void _selectSearchField(SearchField? field) {
    if (_searchField == field) return;
    setState(() => _searchField = field);
    _loadProducts(_searchQuery);
  }

  // ── Selection ─────────────────────────────────────────────────────────────

  void _toggleSelect(Product product) {
    HapticFeedback.lightImpact();
    setState(() {
      if (_selectedCode == product.code) {
        _selectedCode = null;
      } else {
        _selectedCode = product.code;
        // Inicializa controllers para este produto
        _ensureControllers(product);
      }
    });
  }

  void _ensureControllers(Product product) {
    final code = product.code;
    final resolvedPrice = _resolvedPrices[code] ?? product.price;

    if (!_qtyControllers.containsKey(code)) {
      _quantities[code] = 1;
      _qtyControllers[code] = TextEditingController(text: '1');
      _priceControllers[code] =
          TextEditingController(text: resolvedPrice.toStringAsFixed(2));
      _discountPctControllers[code] = TextEditingController(text: '0');
      _discountValControllers[code] = TextEditingController(text: '0,00');
    }

    if (!_priceFocusNodes.containsKey(code)) {
      final node = FocusNode();
      node.addListener(() {
        if (!node.hasFocus) {
          _validateAndResetPrice(product);
        }
      });
      _priceFocusNodes[code] = node;
    }
  }

  void _validateAndResetPrice(Product product) {
    final code = product.code;
    final resolvedPrice = _resolvedPrices[code] ?? product.price;
    final typedText = _priceControllers[code]?.text.replaceAll(',', '.') ?? '';
    final typedPrice = double.tryParse(typedText) ?? resolvedPrice;

    if (typedPrice < resolvedPrice) {
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: Text(
            'O valor só pode ser corrigido para cima! Preço mínimo: R\$ ${resolvedPrice.toStringAsFixed(2)}',
          ),
          backgroundColor: AppColors.warning,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ));
      _priceControllers[code]?.text = resolvedPrice.toStringAsFixed(2);
      _updateDiscountValue(product);
      setState(() {});
    } else {
      _updateDiscountValue(product);
      setState(() {});
    }
  }

  void _incrementQty(Product product) {
    final code    = product.code;
    final current = _quantities[code] ?? 1;
    final next    = current + 1;

    // Bloqueia se ultrapassar o estoque e a empresa não permite venda negativa
    if (!widget.cart.canSellWithoutStock && next > product.stock) {
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
            content: Text(
              'Estoque máximo: ${product.stock.toStringAsFixed(0)} unidade(s)',
            ),
            backgroundColor: AppColors.warning,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ));
      return;
    }

    _quantities[code] = next;
    _qtyControllers[code]?.text = next.toStringAsFixed(0);
    _updateDiscountValue(product);
    setState(() {});
  }

  void _decrementQty(Product product) {
    final code = product.code;
    final current = _quantities[code] ?? 1;
    if (current <= 1) return;
    final next = current - 1;
    _quantities[code] = next;
    _qtyControllers[code]?.text = next.toStringAsFixed(0);
    _updateDiscountValue(product);
    setState(() {});
  }

  void _onDiscountPctChanged(Product product, String value) {
    final pct = double.tryParse(value.replaceAll(',', '.')) ?? 0;
    final fallbackPrice = _resolvedPrices[product.code] ?? product.price;
    final price = double.tryParse(
            _priceControllers[product.code]?.text.replaceAll(',', '.') ?? '') ??
        fallbackPrice;
    final qty = _quantities[product.code] ?? 1;
    // Usa a mesma fórmula de CartItem.discountValue para evitar divergência
    // por ponto flutuante (price × qty × pct/100 ≠ price×qty - price×qty×(1-pct/100)
    // em valores não redondos como 30,89).
    final totalWithDiscount = price * qty * (1 - pct / 100);
    final discVal = price * qty - totalWithDiscount;
    _discountValControllers[product.code]?.text = discVal.toStringAsFixed(2);
    setState(() {});
  }

  void _onDiscountValChanged(Product product, String value) {
    final discVal = double.tryParse(value.replaceAll(',', '.')) ?? 0;
    final fallbackPrice = _resolvedPrices[product.code] ?? product.price;
    final price = double.tryParse(
            _priceControllers[product.code]?.text.replaceAll(',', '.') ?? '') ??
        fallbackPrice;
    final qty = _quantities[product.code] ?? 1;
    final total = price * qty;
    final pct = total > 0 ? discVal / total * 100 : 0;
    // Preserva 2 casas decimais no percentual para que o round-trip
    // valor → % → valor não perca precisão (ex: R$0,89 → 2,88% → R$0,89).
    _discountPctControllers[product.code]?.text = pct.toStringAsFixed(2);
    setState(() {});
  }

  void _updateDiscountValue(Product product) {
    final pct = double.tryParse(
            _discountPctControllers[product.code]
                    ?.text
                    .replaceAll(',', '.') ??
                '') ??
        0;
    final fallbackPrice = _resolvedPrices[product.code] ?? product.price;
    final price = double.tryParse(
            _priceControllers[product.code]?.text.replaceAll(',', '.') ?? '') ??
        fallbackPrice;
    final qty = _quantities[product.code] ?? 1;
    // Mesma fórmula de CartItem.discountValue (consistência de ponto flutuante)
    final totalWithDiscount = price * qty * (1 - pct / 100);
    final discVal = price * qty - totalWithDiscount;
    _discountValControllers[product.code]?.text = discVal.toStringAsFixed(2);
  }

  double _getTotal(Product product) {
    final fallbackPrice = _resolvedPrices[product.code] ?? product.price;
    final price = double.tryParse(
            _priceControllers[product.code]?.text.replaceAll(',', '.') ?? '') ??
        fallbackPrice;
    final qty = _quantities[product.code] ?? 1;
    final pct = double.tryParse(
            _discountPctControllers[product.code]
                    ?.text
                    .replaceAll(',', '.') ??
                '') ??
        0;
    return price * qty * (1 - pct / 100);
  }

  Future<void> _addItem(Product product) async {
    final code = product.code;
    final resolvedPrice = _resolvedPrices[code] ?? product.price;
    final typedText = _priceControllers[code]?.text.replaceAll(',', '.') ?? '';
    final typedPrice = double.tryParse(typedText) ?? resolvedPrice;

    if (typedPrice < resolvedPrice) {
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: Text(
            'O valor só pode ser corrigido para cima! Preço mínimo: R\$ ${resolvedPrice.toStringAsFixed(2)}',
          ),
          backgroundColor: AppColors.warning,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ));
      _priceControllers[code]?.text = resolvedPrice.toStringAsFixed(2);
      _updateDiscountValue(product);
      setState(() {});
      return;
    }

    final qty = _quantities[product.code] ?? 1;
    final pct = double.tryParse(
            _discountPctControllers[product.code]
                    ?.text
                    .replaceAll(',', '.') ??
                '') ??
        0;

    final customPrice = typedPrice != resolvedPrice ? typedPrice : null;
    await widget.cart.addProduct(product, quantity: qty, customPrice: customPrice);
    if (pct > 0) {
      widget.cart.updateDiscount(product.code, pct);
    }

    if (!mounted) return;

    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${product.name} adicionado',
                style: const TextStyle(color: Colors.white),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.success,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );

    // Reset selection
    setState(() => _selectedCode = null);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Produtos'),
        actions: [
          // Filtro de estoque
          Tooltip(
            message: _onlyInStock ? 'Mostrando apenas com estoque' : 'Mostrando todos',
            child: InkWell(
              onTap: () => setState(() => _onlyInStock = !_onlyInStock),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    Icon(
                      _onlyInStock ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                      color: _onlyInStock ? AppColors.success : AppColors.textSecondary,
                      size: 20,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Estoque',
                      style: TextStyle(
                        color: _onlyInStock ? AppColors.success : AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: _onlyInStock ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Botão scanner PDV
          TextButton.icon(
            onPressed: _toggleScanner,
            icon: Icon(
              _scannerMode ? Icons.close_rounded : Icons.qr_code_scanner_rounded,
              color: _scannerMode ? AppColors.error : AppColors.textSecondary,
              size: 20,
            ),
            label: Text(
              _scannerMode ? 'Fechar' : 'Cód. Barras',
              style: TextStyle(
                color: _scannerMode ? AppColors.error : AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
          if (widget.cart.hasItems)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Chip(
                avatar: const Icon(Icons.shopping_cart, size: 16),
                label: Text('${widget.cart.totalItemCount} itens'),
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // ── Scanner PDV (câmera contínua) ─────────────────────────────
          if (_scannerMode && _scannerCtrl != null)
            _buildScannerWidget(),

          // ── Search bar com dropdown de campo ──────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              children: [
                // Dropdown de campo de busca
                _SearchFieldChip(
                  selected: _searchField,
                  onChanged: _selectSearchField,
                ),
                const SizedBox(width: 8),
                // Campo de texto
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: _onSearchChanged,
                    style: AppTypography.body,
                    decoration: InputDecoration(
                      hintText: _searchField == null
                          ? 'Buscar por nome, código, ref...'
                          : 'Buscar por ${_searchField!.label.toLowerCase()}...',
                      prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary),
                      suffixIcon: _searchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 20),
                              onPressed: () {
                                _searchCtrl.clear();
                                _onSearchChanged('');
                              },
                            )
                          : null,
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Sugestões do cliente (se houver) ────────────────────────
          if (_suggestions.isNotEmpty && _searchQuery.isEmpty)
            _buildSuggestionsStrip(),

          // ── Product list ──────────────────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : Builder(builder: (context) {
                    final displayProducts = _onlyInStock 
                        ? _products.where((p) => p.stock > 0).toList() 
                        : _products;
                    
                    if (displayProducts.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.search_off_rounded,
                                size: 56, color: AppColors.textTertiary),
                            const SizedBox(height: 16),
                            Text(
                              _products.isNotEmpty && _onlyInStock
                                  ? 'Nenhum produto em estoque'
                                  : 'Nenhum produto encontrado',
                              style: AppTypography.body
                                  .copyWith(color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      );
                    }
                    
                    return ListView.builder(
                        itemCount: displayProducts.length,
                        padding: const EdgeInsets.only(bottom: 80),
                        itemBuilder: (ctx, i) =>
                            _buildProductCard(displayProducts[i]),
                      );
                  }),
          ),
        ],
      ),
    );
  }

  // ── Scanner PDV Widget ─────────────────────────────────────────────────

  Widget _buildScannerWidget() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: 220,
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border.all(
          color: _scanFlash ? AppColors.success : Colors.transparent,
          width: _scanFlash ? 4 : 0,
        ),
      ),
      child: Stack(
        children: [
          // Câmera
          ClipRect(
            child: MobileScanner(
              controller: _scannerCtrl!,
              onDetect: _onBarcodeDetected,
            ),
          ),

          // Header overlay
          Positioned(
            top: 0, left: 0, right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withOpacity(0.7), Colors.transparent],
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.qr_code_scanner_rounded,
                      color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'Modo PDV — Aponte para o código de barras',
                    style: TextStyle(
                      color: Colors.white, fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  if (_scanCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.success,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$_scanCount lido${_scanCount > 1 ? 's' : ''}',
                        style: const TextStyle(
                          color: Colors.white, fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Linha de scan animada central
          Positioned(
            top: 105, left: 40, right: 40,
            child: Container(
              height: 2,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    AppColors.primary.withOpacity(0.8),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Suggestions Strip ──────────────────────────────────────────────────

  Widget _buildSuggestionsStrip() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.04),
        border: Border(
          bottom: BorderSide(color: AppColors.primary.withOpacity(0.12)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded, size: 14, color: AppColors.primary.withOpacity(0.7)),
              const SizedBox(width: 6),
              Text(
                'Sugestões para este cliente',
                style: AppTypography.caption.copyWith(
                  color: AppColors.primary.withOpacity(0.7),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 54,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _suggestions.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final s = _suggestions[i];
                final code = s['product_code'] as String? ?? '';
                final name = s['product_name'] as String? ?? code;
                final qty = (s['total_qty'] as num?)?.toDouble() ?? 0;

                return GestureDetector(
                  onTap: () {
                    _searchCtrl.text = code;
                    _selectSearchField(SearchField.code);
                    _onSearchChanged(code);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.primary.withOpacity(0.15)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          name,
                          style: AppTypography.body.copyWith(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${qty.toStringAsFixed(0)}x comprado',
                          style: AppTypography.badge.copyWith(
                            fontSize: 9,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Product Card ────────────────────────────────────────────────────────

  Widget _buildProductCard(Product product) {
    final isSelected = _selectedCode == product.code;
    final isInStock = product.isInStock;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: isSelected ? AppColors.primary : AppColors.border,
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: [
          // ── Header row: name + checkbox ──────────────────────────────
          InkWell(
            onTap: (isInStock || widget.cart.canSellWithoutStock)
                ? () => _toggleSelect(product)
                : null,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppRadius.md),
              bottom: isSelected ? Radius.zero : Radius.circular(AppRadius.md),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  // Product info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          style: AppTypography.bodyBold.copyWith(
                            color: (isInStock || widget.cart.canSellWithoutStock)
                              ? AppColors.textPrimary
                              : AppColors.textTertiary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                product.category ?? 'PADRÃO',
                                style: AppTypography.caption
                                    .copyWith(color: AppColors.primary),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (product.stock > 0) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.success.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'Est: ${product.stock % 1 == 0 ? product.stock.toInt().toString() : product.stock.toStringAsFixed(2)} UN',
                                  style: AppTypography.caption.copyWith(
                                    color: AppColors.success,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Circle checkbox: sempre visível se em estoque ou estoque liberado
                  if (isInStock || widget.cart.canSellWithoutStock) () {
                    final isInCart = widget.cart.items
                        .any((i) => i.product.code == product.code);
                    final filled = isSelected || isInCart;
                    return Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: filled
                              ? AppColors.primary
                              : AppColors.textSecondary,
                          width: 2,
                        ),
                        color: filled
                            ? AppColors.primary
                            : Colors.transparent,
                      ),
                      child: filled
                          ? const Icon(Icons.check,
                              size: 16, color: Colors.white)
                          : null,
                    );
                  }(),
                ],
              ),
            ),
          ),

          // ── Inline controls (when selected) ──────────────────────────
          if (isSelected && (isInStock || widget.cart.canSellWithoutStock)) _buildInlineControls(product),
        ],
      ),
    );
  }

  // ── Inline Controls ───────────────────────────────────────────────────────

  Widget _buildInlineControls(Product product) {
    final code = product.code;
    _ensureControllers(product);

    final total = _getTotal(product);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceSecondary,
        borderRadius:
            BorderRadius.vertical(bottom: Radius.circular(AppRadius.md)),
      ),
      child: Column(
        children: [
          const Divider(height: 1, color: AppColors.border),

          // ── REF + ESTOQUE row ───────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Row(
              children: [
                Text('REF', style: AppTypography.caption.copyWith(color: AppColors.textTertiary)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(product.reference ?? product.code,
                      style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
                ),
                Text('ESTOQUE', style: AppTypography.caption.copyWith(color: AppColors.textTertiary)),
                const SizedBox(width: 8),
                Text(
                  product.stock.toStringAsFixed(0),
                  style: AppTypography.bodyBold.copyWith(
                    color: product.stock > 0
                        ? AppColors.textPrimary
                        : AppColors.error,
                  ),
                ),
              ],
            ),
          ),

          // ── Quantity + Valor row ────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Row(
              children: [
                // Quantity section
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('QUANTIDADE',
                          style: AppTypography.caption
                              .copyWith(color: AppColors.textTertiary)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _circleButton(Icons.remove,
                              onTap: () => _decrementQty(product)),
                          SizedBox(
                            width: 56,
                            child: TextField(
                              controller: _qtyControllers[code],
                              textAlign: TextAlign.center,
                              keyboardType: TextInputType.number,
                              style: AppTypography.bodyBold,
                              decoration: InputDecoration(
                                isDense: true,
                                contentPadding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide:
                                      const BorderSide(color: AppColors.border),
                                ),
                              ),
                              onChanged: (v) {
                                var val = double.tryParse(v) ?? 1;
                                // Clamp ao estoque quando não permite negativo
                                if (!widget.cart.canSellWithoutStock &&
                                    product.stock > 0 &&
                                    val > product.stock) {
                                  val = product.stock;
                                  _qtyControllers[code]?.text =
                                      val.toStringAsFixed(0);
                                }
                                _quantities[code] = val;
                                _updateDiscountValue(product);
                                setState(() {});
                              },
                            ),
                          ),
                          _circleButton(Icons.add,
                              onTap: () => _incrementQty(product)),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 16),

                // Valor section
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('VALOR',
                          style: AppTypography.caption
                              .copyWith(color: AppColors.textTertiary)),
                      const SizedBox(height: 4),
                      TextField(
                        controller: _priceControllers[code],
                        focusNode: _priceFocusNodes[code],
                        readOnly: false,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        style: AppTypography.bodyBold.copyWith(
                          color: AppColors.textPrimary,
                        ),
                        decoration: InputDecoration(
                          prefixText: 'R\$ ',
                          prefixStyle: AppTypography.bodyBold.copyWith(
                            color: AppColors.textPrimary,
                          ),
                          isDense: true,
                          filled: true,
                          fillColor: AppColors.surface,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide:
                                const BorderSide(color: AppColors.border),
                          ),
                        ),
                        onSubmitted: (_) => _validateAndResetPrice(product),
                        onChanged: (_) {
                          _updateDiscountValue(product);
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Discount row ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Row(
              children: [
                // % Desconto
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('% DESCONTO',
                          style: AppTypography.caption
                              .copyWith(color: AppColors.textTertiary)),
                      const SizedBox(height: 4),
                      TextField(
                        controller: _discountPctControllers[code],
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        style: AppTypography.body,
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide:
                                const BorderSide(color: AppColors.border),
                          ),
                        ),
                        onChanged: (v) =>
                            _onDiscountPctChanged(product, v),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),

                // Valor Desconto
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('VALOR DESCONTO',
                          style: AppTypography.caption
                              .copyWith(color: AppColors.textTertiary)),
                      const SizedBox(height: 4),
                      TextField(
                        controller: _discountValControllers[code],
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        style: AppTypography.body,
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide:
                                const BorderSide(color: AppColors.border),
                          ),
                        ),
                        onChanged: (v) =>
                            _onDiscountValChanged(product, v),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Total + Add button ────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('TOTAL',
                        style: AppTypography.caption
                            .copyWith(color: AppColors.textTertiary)),
                    Text(
                      _currencyFmt.format(total),
                      style: AppTypography.headingMedium,
                    ),
                  ],
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () => _addItem(product),
                  icon: const Icon(Icons.add_shopping_cart, size: 18),
                  label: const Text('Adicionar item'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _circleButton(IconData icon, {required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.primary),
        ),
        child: Icon(icon, size: 18, color: AppColors.primary),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SearchFieldChip — Dropdown compacto para seleção do campo de busca
// ─────────────────────────────────────────────────────────────────────────────

class _SearchFieldChip extends StatelessWidget {
  final SearchField? selected;
  final ValueChanged<SearchField?> onChanged;

  const _SearchFieldChip({
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final label = selected?.label ?? 'Todos';

    return Material(
      color: selected != null
          ? AppColors.actionPrimary.withOpacity(0.1)
          : AppColors.surfaceSecondary,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _showPicker(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.filter_list_rounded,
                size: 16,
                color: selected != null
                    ? AppColors.actionPrimary
                    : AppColors.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected != null
                      ? AppColors.actionPrimary
                      : AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.expand_more_rounded,
                size: 16,
                color: selected != null
                    ? AppColors.actionPrimary
                    : AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  const Icon(Icons.filter_list_rounded, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Buscar por...',
                    style: AppTypography.cardTitle,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Opção "Todos"
            _buildOption(ctx, label: 'Todos os campos', value: null),
            const Divider(height: 1, indent: 16, endIndent: 16),

            // Opções por campo
            ...SearchField.values.map(
              (f) => _buildOption(ctx, label: f.label, value: f),
            ),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildOption(
    BuildContext context, {
    required String label,
    required SearchField? value,
  }) {
    final isSelected = selected == value;

    return ListTile(
      dense: true,
      leading: Icon(
        isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
        color: isSelected ? AppColors.actionPrimary : AppColors.textTertiary,
        size: 20,
      ),
      title: Text(
        label,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          color: isSelected ? AppColors.actionPrimary : AppColors.textPrimary,
        ),
      ),
      onTap: () {
        Navigator.of(context).pop();
        onChanged(value);
      },
    );
  }
}

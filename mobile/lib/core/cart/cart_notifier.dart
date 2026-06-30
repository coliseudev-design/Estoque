/// CartNotifier — State management do carrinho de compras.
///
/// Gerencia o estado do carrinho em memória e persiste rascunho
/// automaticamente no SQLite a cada alteração (auto-save).
///
/// REGRA (Rule-06 Clean Architecture): Este notifier contém a lógica
/// de negócio do carrinho. O OrderRepository é infraestrutura.
/// REGRA (offline-first): Qualquer alteração é salva ANTES de notificar a UI.
library;

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../repositories/models/models.dart';
import '../repositories/models/seller.dart';
import '../repositories/models/payment_condition.dart';
import '../repositories/order_repository.dart';
import '../repositories/product_repository.dart';
import '../repositories/customer_repository.dart';
import '../services/discount_service.dart';
import '../services/price_service.dart';
import '../services/company_settings_service.dart';
import '../session/session_service.dart';
import 'package:get_it/get_it.dart';
import 'package:coliseu_speed/core/config/app_config_service.dart';

class CartNotifier extends ChangeNotifier {
  final OrderRepository _repo;
  final PriceService    _priceService;

  static const _uuid = Uuid();

  // ── Estado do carrinho ─────────────────────────────────────────────────────
  String _orderId      = _uuid.v4();   // UUID gerado na criação do notifier
  bool   _isEditingExisting = false;
  String _customerId   = '';
  String _customerName = '';
  String? _notes;
  final List<CartItem> _items = [];
  bool    _isSaving     = false;
  String? _errorMessage;

  // WARNING-2 fix: debounce para operações de digitação (setNotes, updateDiscount, etc.)
  // Evita dezenas de writes SQLite por segundo ao editar nota ou alterar desconto.
  Timer? _saveDebounce;

  // Desconto no pedido (global)
  double       _orderDiscountInput = 0;
  DiscountMode _orderDiscountMode  = DiscountMode.percent;

  // Pagamento e operação
  String? _paymentSpeciesId;
  String? _paymentSpeciesName;
  String? _paymentConditionId;
  String? _paymentConditionName;
  int?    _paymentDays;
  int?    _paymentInstallments;      // FORMA_PGTO.PARCELAS
  int?    _paymentDaysPerInstallment; // FORMA_PGTO.DIAS_PARCELAS
  int?    _paymentEntryDays;         // FORMA_PGTO.DIAS_ENTRADA
  String? _naturezaId;
  String? _naturezaDescricao;

  /// ID da tabela de preço do cliente selecionado (CLIENTES.ID_TABELA).
  /// null = cliente sem tabela → usa preço base do produto.
  String? _priceTableId;
  String? _activeTableName;

  CartNotifier({required OrderRepository repo, PriceService? priceService})
      : _repo         = repo,
        _priceService = priceService ?? PriceService() {
    _orderId = _uuid.v4();
  }

  // ── Getters ────────────────────────────────────────────────────────────────

  String  get orderId          => _orderId;
  String  get customerId       => _customerId;
  String  get customerName     => _customerName;
  String? get notes            => _notes;
  bool    get isSaving         => _isSaving;
  String? get errorMessage     => _errorMessage;

  String? get paymentSpeciesId   => _paymentSpeciesId;
  String? get paymentSpeciesName => _paymentSpeciesName;
  String? get paymentConditionId => _paymentConditionId;
  String? get paymentConditionName => _paymentConditionName;
  int?    get paymentDays        => _paymentDays;
  int?    get paymentInstallments      => _paymentInstallments;
  int?    get paymentDaysPerInstallment => _paymentDaysPerInstallment;
  int?    get paymentEntryDays         => _paymentEntryDays;
  String? get naturezaId         => _naturezaId;
  String? get naturezaDescricao  => _naturezaDescricao;

  /// ID da tabela de preço ativa (do cliente selecionado).
  String? get priceTableId      => _priceTableId;

  /// Nome da tabela de preço ativa, ou null se não houver.
  String? get activeTableName   => _activeTableName;

  /// True se a empresa usa tabela de preço (modo product ou prompt).
  bool get usePriceTable {
    try {
      return GetIt.instance.isRegistered<CompanySettingsService>()
          ? GetIt.instance<CompanySettingsService>().usePriceTable
          : true; // default: compatibilidade legada
    } catch (_) { return true; }
  }

  /// True se a empresa usa modo prompt (vendedor escolhe a tabela).
  bool get isPriceTablePrompt {
    try {
      return GetIt.instance.isRegistered<CompanySettingsService>()
          ? GetIt.instance<CompanySettingsService>().promptPriceTable
          : false;
    } catch (_) { return false; }
  }

  /// True se a empresa permite vender produtos com estoque zero ou negativo.
  ///
  /// false (padrão): `addProduct` bloqueia; UI esmaéce o card.
  /// true:            produto pode ser adicionado mesmo com `isInStock == false`;
  ///                  UI exibe badge laranja "Sem Estoque" mas mantém clicável.
  bool get canSellWithoutStock {
    try {
      return GetIt.instance.isRegistered<CompanySettingsService>()
          ? GetIt.instance<CompanySettingsService>().allowNegativeStock
          : false; // default: bloqueia (comportamento legado)
    } catch (_) { return false; }
  }

  /// True se forma de pagamento foi selecionada.
  bool get hasPaymentSpecies => _paymentSpeciesId != null;

  /// Cópia imutável da lista de itens.
  List<CartItem> get items => List.unmodifiable(_items);

  /// Total com descontos já aplicados.
  double get total => _items.fold(0, (sum, i) => sum + i.totalPrice);

  /// Soma dos descontos absolutos de todos os itens.
  double get totalDiscountValue =>
      _items.fold(0, (sum, i) => sum + i.discountValue);

  /// Desconto percentual médio ponderado (para rodapé).
  double get totalDiscountPercent {
    final gross = _items.fold(0.0, (s, i) => s + i.product.price * i.quantity);
    if (gross == 0) return 0;
    return totalDiscountValue / gross * 100;
  }

  /// True se há ao menos um item no carrinho.
  bool get hasItems => _items.isNotEmpty;

  /// Total de unidades (para badge no ícone da aba).
  int get totalItemCount => _items.fold(0, (sum, i) => sum + i.quantity.round());

  // ── Desconto global do pedido ─────────────────────────────────────────────

  double       get orderDiscountInput => _orderDiscountInput;
  DiscountMode get orderDiscountMode  => _orderDiscountMode;

  /// Valor absoluto do desconto global do pedido (em R$).
  double get orderDiscountValue {
    final itemsTotal = _items.fold(0.0, (sum, i) => sum + i.totalPrice);
    if (_orderDiscountInput <= 0) return 0;
    if (_orderDiscountMode == DiscountMode.percent) {
      return itemsTotal * (_orderDiscountInput.clamp(0, 100) / 100);
    }
    return _orderDiscountInput.clamp(0, itemsTotal);
  }

  /// Percentual equivalente do desconto global.
  double get orderDiscountPercent {
    final itemsTotal = _items.fold(0.0, (sum, i) => sum + i.totalPrice);
    if (_orderDiscountInput <= 0 || itemsTotal == 0) return 0;
    if (_orderDiscountMode == DiscountMode.percent) {
      return _orderDiscountInput.clamp(0, 100);
    }
    return (_orderDiscountInput.clamp(0, itemsTotal) / itemsTotal * 100);
  }

  /// Total final = itens com desconto por item - desconto global.
  double get grandTotal {
    final itemsTotal = _items.fold(0.0, (sum, i) => sum + i.totalPrice);
    return (itemsTotal - orderDiscountValue).clamp(0, double.infinity);
  }

  // ── Configuração do pedido ─────────────────────────────────────────────────

  /// Define o cliente para o pedido atual.
  ///
  /// [priceTableId] é o ID da tabela de preço vinculada ao cliente
  /// (CLIENTES.ID_TABELA). Quando não nulo, os preços serão resolvidos
  /// pela tabela ao adicionar produtos ao carrinho.
  Future<void> setCustomer({
    required String id,
    required String name,
    String? priceTableId,
  }) async {
    _customerId     = id;
    _customerName   = name;
    _priceTableId   = priceTableId;
    _activeTableName = priceTableId != null
        ? await _priceService.getActiveTableName(priceTableId)
        : null;
    notifyListeners();
  }

  /// Define a espécie de pagamento (Forma de Pagamento) do pedido.
  ///
  /// Campo obrigatório antes de confirmar. Filtramos do Firebird apenas
  /// espécies com MOB_ACESSO = 'S'.
  void setPaymentSpecies({
    required String id,
    required String name,
    int? days,
  }) {
    _paymentSpeciesId   = id;
    _paymentSpeciesName = name;
    _paymentDays        = days;
    notifyListeners();
  }

  /// Define a condição de pagamento (parcelamento).
  /// Aceita o objeto completo [condition] para capturar parcelas, dias, etc.
  void setPaymentCondition(PaymentCondition? condition) {
    _paymentConditionId           = condition?.id;
    _paymentConditionName         = condition?.descricao;
    _paymentInstallments          = condition?.parcelas;
    _paymentDaysPerInstallment    = condition?.diasParcelas;
    _paymentEntryDays             = condition?.diasEntrada;
    notifyListeners();
  }

  /// Define a natureza de operação do pedido (nullable — natureza é opcional).
  ///
  /// Passar null para [id] e [descricao] limpa a seleção atual.
  void setNatureza({String? id, String? descricao}) {
    _naturezaId        = id;
    _naturezaDescricao = descricao;
    notifyListeners();
  }

  /// Define manualmente a tabela de preço a usar no pedido (modo prompt).
  ///
  /// Usado quando `priceTableMode == 'prompt'` e o vendedor seleciona
  /// a tabela via dropdown na tela de novo pedido.
  Future<void> setPriceTableManual(String? tableId, String? tableName) async {
    _priceTableId    = tableId;
    _activeTableName = tableName;
    notifyListeners();
  }

  // ── Operações do carrinho ──────────────────────────────────────────────────

  /// Adiciona um produto ao carrinho.
  ///
  /// Se o produto já existir, incrementa a quantidade.
  /// Persiste o rascunho automaticamente.
  ///
  /// **Validações de estoque (quando `canSellWithoutStock == false`):**
  ///   - Bloqueia se `!product.isInStock` (estoque zero/negativo)
  ///   - Bloqueia se `qty atual + quantity > product.stock` (teto de estoque)
  ///
  /// @param product   Produto a adicionar.
  /// @param quantity  Quantidade (padrão 1).
  Future<void> addProduct(Product product, {double quantity = 1, bool bypassStockValidation = false, double? customPrice}) async {
    // 1) Bloqueia produto sem estoque quando a empresa não permite negativo
    if (!bypassStockValidation && !product.isInStock && !canSellWithoutStock) return;

    // 2) Bloqueia quando a qty acumulada ultrapassaria o estoque disponível
    if (!bypassStockValidation && !canSellWithoutStock && product.stock > 0) {
      final currentQty = _items
          .where((i) => i.product.code == product.code)
          .fold(0.0, (sum, i) => sum + i.quantity);
      if (currentQty + quantity > product.stock) return;
    }

    // Resolve preço: tabela do cliente (se modo product/prompt) ou base (modo none) ou customPrice se fornecido
    final effectiveTableId = usePriceTable ? _priceTableId : null;
    final resolvedPrice = customPrice ?? await _priceService.resolvePrice(
      basePrice:    product.price,
      productCode:  product.code,
      priceTableId: effectiveTableId,
    );

    // Usa produto com o preço resolvido (pode ser da tabela ou o base ou customPrice)
    final productToAdd = resolvedPrice != product.price
        ? _ProductWithOverriddenPrice(product, resolvedPrice)
        : product;

    final existingIdx = _items.indexWhere((i) => i.product.code == product.code);
    if (existingIdx >= 0) {
      if (customPrice != null) {
        _items[existingIdx] = CartItem(
          product: productToAdd,
          quantity: _items[existingIdx].quantity + quantity,
          discount: _items[existingIdx].discount,
          discountMode: _items[existingIdx].discountMode,
          rawDiscountInput: _items[existingIdx].rawDiscountInput,
        );
      } else {
        _items[existingIdx] = _items[existingIdx].copyWith(
          quantity: _items[existingIdx].quantity + quantity,
        );
      }
    } else {
      _items.add(CartItem(product: productToAdd, quantity: quantity));
    }

    await _autoSave();
    notifyListeners();
  }

  /// Atualiza a quantidade de um item. Se [quantity] <= 0 remove o item.
  Future<void> updateQuantity(String productCode, double quantity) async {
    if (quantity <= 0) {
      await removeItem(productCode);
      return;
    }
    final idx = _items.indexWhere((i) => i.product.code == productCode);
    if (idx < 0) return;

    _items[idx] = _items[idx].copyWith(quantity: quantity);
    notifyListeners();
    _scheduleSave(); // debounced — slider/stepper pode disparar muitos eventos seguidos
  }

  /// Aplica desconto a um item específico.
  ///
  /// Suporta dois modos:
  /// - [DiscountMode.percent]: inputValue é um percentual (0–100)
  /// - [DiscountMode.value]:   inputValue é um valor fixo em R$ por unidade
  ///
  /// O desconto é clampado respeitando (em ordem):
  /// 1. [Product.maxDiscount] — teto do produto
  /// 2. [Seller.maxDiscount]  — teto do vendedor (passado via [seller])
  /// 3. [Product.priceMin]    — piso de preço mínimo
  /// 4. [Product.priceCost]   — piso de custo (margem zero)
  Future<DiscountResult> updateDiscount(
    String productCode,
    double inputValue, {
    DiscountMode mode   = DiscountMode.percent,
    Seller?      seller,
  }) async {
    final idx = _items.indexWhere((i) => i.product.code == productCode);
    if (idx < 0) return DiscountResult(percent: 0, valuePerUnit: 0, unitPriceAfterDiscount: 0, totalPrice: 0, wasClamped: false, maxAllowedPercent: 100);

    final item   = _items[idx];
    final svc    = DiscountService();
    final result = svc.calculate(
      product:    item.product,
      quantity:   item.quantity,
      inputValue: inputValue,
      mode:       mode,
      seller:     seller,
    );

    _items[idx] = item.copyWith(
      discount:         result.percent,
      discountMode:     mode,
      rawDiscountInput: inputValue,
    );
    notifyListeners();
    _scheduleSave(); // debounced — slider de desconto gera eventos contínuos
    return result;
  }

  /// Remove um item do carrinho pelo código do produto.
  Future<void> removeItem(String productCode) async {
    _items.removeWhere((i) => i.product.code == productCode);
    await _autoSave();
    notifyListeners();
  }

  /// Atualiza as observações do pedido.
  Future<void> setNotes(String? value) async {
    _notes = (value?.trim().isEmpty ?? true) ? null : value!.trim();
    notifyListeners();
    _scheduleSave(); // debounced — digitação na nota dispara a cada caractere
  }

  /// Define desconto global do pedido.
  ///
  /// @param value  Valor do desconto (% ou R$ dependendo do [mode]).
  /// @param mode   Modo: percentual ou valor fixo.
  Future<void> setOrderDiscount(double value, {DiscountMode mode = DiscountMode.percent}) async {
    _orderDiscountInput = value;
    _orderDiscountMode  = mode;
    notifyListeners();
    _scheduleSave(); // debounced — campo de desconto global pode mudar rapidamente
  }

  // ── Auto-save ──────────────────────────────────────────────────────────────

  /// Agenda um auto-save com debounce de 300ms.
  ///
  /// Chamado em operações contínuas (digitação em nota, sliders de desconto).
  /// Garante no máximo 1 write por 300ms de inatividade.
  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 300), _autoSave);
  }

  /// Persiste o rascunho atual no SQLite imediatamente.
  ///
  /// NÃO lança exceção — registra o erro e continua (UX não bloqueia).
  Future<void> _autoSave() async {
    if (_customerId.isEmpty) {
      debugPrint('[CartNotifier._autoSave] Abortado: customerId vazio. orderId=$_orderId');
      return;
    }
    // Garante que sempre temos um UUID válido
    if (_orderId.isEmpty) _orderId = _uuid.v4();

    _isSaving = true;
    try {
      final config = GetIt.I<AppConfigService>();
      final companyId = await config.getBranchId() ?? GetIt.I<SessionService>().activeSession?.companyId ?? '1';
      await _repo.saveDraft(
        orderId:            _orderId,
        companyId:          companyId,
        customerId:         _customerId,
        customerName:       _customerName,
        items:              _items,
        notes:              _notes,
        paymentSpeciesId:   _paymentSpeciesId,
        paymentSpeciesName: _paymentSpeciesName,
        paymentConditionId: _paymentConditionId,
        paymentConditionName: _paymentConditionName,
        paymentDays:        _paymentDays,
        paymentInstallments:      _paymentInstallments,
        paymentDaysPerInstallment: _paymentDaysPerInstallment,
        paymentEntryDays:          _paymentEntryDays,
        naturezaId:         _naturezaId,
        naturezaDescricao:  _naturezaDescricao,
        isDraft:            true,
        orderDiscountInput: _orderDiscountInput,
        orderDiscountMode:  _orderDiscountMode.name,
      );
      _errorMessage = null;
    } catch (e, st) {
      // Loga o erro COMPLETO para diagnóstico — _autoSave não pode relançar
      // (a UI não deve travar por falha de auto-save), mas precisa ser visível.
      debugPrint('[CartNotifier._autoSave] ERRO ao salvar rascunho!');
      debugPrint('  orderId      : $_orderId');
      debugPrint('  customerId   : $_customerId');
      debugPrint('  itens        : ${_items.length}');
      debugPrint('  Exceção      : ${e.runtimeType}: $e');
      debugPrint('  StackTrace   :\n$st');
      _errorMessage = 'Erro ao salvar rascunho: $e';
    } finally {
      _isSaving = false;
    }
  }

  // ── Confirmação ────────────────────────────────────────────────────────────

  /// Confirma o pedido, tornando-o imutável e enfileirando para sync.
  ///
  /// @param sellerId  ID do vendedor (da sessão).
  /// @param companyId ID da empresa (da sessão).
  /// @throws [StateError] se carrinho vazio, sem cliente ou sem forma de pagamento.
  Future<Order> confirmOrder({
    required String sellerId,
    required String companyId,
  }) async {
    if (!hasItems)           throw StateError('Carrinho vazio.');
    if (_customerId.isEmpty) throw StateError('Cliente não definido.');
    if (!hasPaymentSpecies)  throw StateError('Forma de pagamento não selecionada.');

    // Garante que o rascunho existe no SQLite ANTES de qualquer leitura.
    // _autoSave() silencia erros internamente — por isso verificamos
    // explicitamente que o pedido foi persistido antes de confirmar.
    if (_orderId.isEmpty) _orderId = _uuid.v4();
    await _autoSave();

    // Verifica se o save realmente gravou o pedido. _autoSave() pode
    // retornar sem salvar se _customerId estiver vazio ou se ocorreu
    // um erro de banco de dados silenciado.
    final savedOrder = await _repo.getById(_orderId);
    if (savedOrder == null) {
      // Tenta um segundo save forçado como fallback
      debugPrint('[CartNotifier] Auto-save não persistiu o pedido $_orderId. Tentando novamente...');
      final config = GetIt.I<AppConfigService>();
      final fallbackCompanyId = await config.getBranchId() ?? GetIt.I<SessionService>().activeSession?.companyId ?? '1';
      await _repo.saveDraft(
        orderId:            _orderId,
        companyId:          fallbackCompanyId,
        customerId:         _customerId,
        customerName:       _customerName,
        items:              _items,
        notes:              _notes,
        paymentSpeciesId:   _paymentSpeciesId,
        paymentSpeciesName: _paymentSpeciesName,
        paymentConditionId: _paymentConditionId,
        paymentConditionName: _paymentConditionName,
        paymentDays:        _paymentDays,
        paymentInstallments:      _paymentInstallments,
        paymentDaysPerInstallment: _paymentDaysPerInstallment,
        paymentEntryDays:          _paymentEntryDays,
        naturezaId:         _naturezaId,
        naturezaDescricao:  _naturezaDescricao,
        isDraft:            true,
        orderDiscountInput: _orderDiscountInput,
        orderDiscountMode:  _orderDiscountMode.name,
      );
    }

    final order = await _repo.confirmOrder(
      orderId:            _orderId,
      sellerId:           sellerId,
      companyId:          companyId,
      paymentSpeciesId:   _paymentSpeciesId!,
      paymentSpeciesName: _paymentSpeciesName!,
      paymentConditionId: _paymentConditionId,
      paymentConditionName: _paymentConditionName,
      paymentDays:        _paymentDays,
      paymentInstallments:      _paymentInstallments,
      paymentDaysPerInstallment: _paymentDaysPerInstallment,
      paymentEntryDays:          _paymentEntryDays,
      naturezaId:         _naturezaId,
      discountPercent:    totalDiscountPercent + orderDiscountPercent,
      discountValue:      totalDiscountValue + orderDiscountValue,
      grandTotal:         grandTotal,
    );

    _reset();
    notifyListeners();
    return order;
  }

  // ── Reset ──────────────────────────────────────────────────────────────────

  /// Salva o carrinho como orçamento (draft). Não enfileira para sync.
  ///
  /// @throws [StateError] se carrinho vazio, sem cliente ou sem pagamento.
  Future<Order> saveAsQuote() async {
    if (!hasItems)           throw StateError('Carrinho vazio.');
    if (_customerId.isEmpty) throw StateError('Cliente não definido.');

    final config = GetIt.I<AppConfigService>();
    final draftCompanyId = await config.getBranchId() ?? GetIt.I<SessionService>().activeSession?.companyId ?? '1';
    final order = await _repo.saveDraft(
      orderId:            _orderId,
      companyId:          draftCompanyId,
      customerId:         _customerId,
      customerName:       _customerName,
      items:              _items,
      notes:              _notes,
      paymentSpeciesId:   _paymentSpeciesId,
      paymentSpeciesName: _paymentSpeciesName,
      paymentConditionId: _paymentConditionId,
      paymentConditionName: _paymentConditionName,
      paymentDays:        _paymentDays,
      paymentInstallments:      _paymentInstallments,
      paymentDaysPerInstallment: _paymentDaysPerInstallment,
      paymentEntryDays:          _paymentEntryDays,
      naturezaId:         _naturezaId,
      naturezaDescricao:  _naturezaDescricao,
      isDraft:            true,
      orderDiscountInput: _orderDiscountInput,
      orderDiscountMode:  _orderDiscountMode.name,
    );

    _reset();
    notifyListeners();
    return order;
  }

  /// Carrega um pedido/orçamento existente no carrinho para edição.
  ///
  /// @param order  O pedido/orçamento a carregar.
  Future<void> loadFromOrder(Order order) async {
    _reset();
    _isEditingExisting  = true;
    _orderId            = order.id;
    _customerId         = order.customerId;
    _customerName       = order.customerName;
    _notes              = order.notes;
    _paymentSpeciesId   = order.paymentSpeciesId;
    _paymentSpeciesName = order.paymentSpeciesName;
    _paymentConditionId        = order.paymentConditionId;
    _paymentConditionName      = order.paymentConditionName;
    _paymentDays               = order.paymentDays;
    _paymentInstallments       = order.paymentInstallments;
    _paymentDaysPerInstallment = order.paymentDaysPerInstallment;
    _paymentEntryDays          = order.paymentEntryDays;
    _naturezaId        = order.naturezaId;
    _naturezaDescricao = order.naturezaDescricao;

    // Restaura desconto global do pedido (se persistido)
    _orderDiscountInput = order.orderDiscountInput;
    _orderDiscountMode  = order.orderDiscountMode == 'value'
        ? DiscountMode.value
        : DiscountMode.percent;

    for (final item in order.items) {
      final product = Product(
        code:  item.productCode,
        name:  item.productName,
        price: item.unitPrice,
        stock: 1,
      );
      await addProduct(product, quantity: item.quantity);
      // Restaura desconto usando o modo original e o input bruto
      if (item.discount > 0) {
        final mode = item.discountMode == 'value'
            ? DiscountMode.value
            : DiscountMode.percent;
        final input = item.rawDiscountInput > 0
            ? item.rawDiscountInput
            : item.discount; // fallback: usa % se rawInput não foi salvo
        await updateDiscount(item.productCode, input, mode: mode);
      }
    }

    notifyListeners();
  }

  /// Clona um pedido existente, gerando um novo UUID e atualizando os preços
  /// de todos os produtos com base na última sincronização do catálogo.
  /// Os descontos são resetados para zero.
  /// Retorna um [CloneResult] contendo alertas sobre estoque e itens removidos.
  Future<CloneResult> cloneFromOrder(Order order) async {
    _reset(); // Gera novo orderId UUID e limpa dados
    
    final customerRepo = GetIt.I<CustomerRepository>();
    final customer = await customerRepo.getById(order.customerId);
    
    _customerId           = order.customerId;
    _customerName         = order.customerName;
    _priceTableId         = customer?.priceTableId;
    _activeTableName      = _priceTableId != null
        ? await _priceService.getActiveTableName(_priceTableId!)
        : null;
    
    _notes                = order.notes;
    _paymentSpeciesId     = order.paymentSpeciesId;
    _paymentSpeciesName   = order.paymentSpeciesName;
    _paymentConditionId   = order.paymentConditionId;
    _paymentConditionName = order.paymentConditionName;
    _paymentDays          = order.paymentDays;
    _paymentInstallments  = order.paymentInstallments;
    _paymentDaysPerInstallment = order.paymentDaysPerInstallment;
    _paymentEntryDays     = order.paymentEntryDays;
    _naturezaId           = order.naturezaId;
    _naturezaDescricao    = order.naturezaDescricao;
    
    // Conforme resposta 2, resetamos os descontos globais do pedido
    _orderDiscountInput   = 0.0;
    _orderDiscountMode    = DiscountMode.percent;

    final productRepo = GetIt.I<ProductRepository>();
    final outOfStockProducts = <String>[];
    final missingProducts    = <String>[];

    for (final item in order.items) {
      final product = await productRepo.getByCode(item.productCode);
      if (product != null) {
        // Conforme resposta 1, clonamos mesmo sem estoque (Opção C),
        // mas coletamos para avisar quais itens não possuem estoque.
        if (!product.isInStock) {
          outOfStockProducts.add(product.name);
        }
        
        // Adiciona ao carrinho ignorando a validação de estoque
        await addProduct(product, quantity: item.quantity, bypassStockValidation: true);
      } else {
        // Conforme resposta 3, exibe alerta e NÃO inclui o item se removido do catálogo
        missingProducts.add(item.productName);
      }
    }
    
    await _autoSave();
    notifyListeners();
    
    return CloneResult(
      outOfStockProducts: outOfStockProducts,
      missingProducts:    missingProducts,
    );
  }

  void _reset() {
    _saveDebounce?.cancel(); // cancela timer pendente ao resetar o carrinho
    _isEditingExisting  = false;
    _orderId            = _uuid.v4();
    _customerId         = '';
    _customerName       = '';
    _notes              = null;
    _paymentSpeciesId   = null;
    _paymentSpeciesName = null;
    _paymentConditionId   = null;
    _paymentConditionName = null;
    _paymentDays          = null;
    _paymentInstallments       = null;
    _paymentDaysPerInstallment  = null;
    _paymentEntryDays           = null;
    _naturezaId         = null;
    _naturezaDescricao  = null;
    _priceTableId       = null;
    _activeTableName    = null;
    _orderDiscountInput = 0;
    _orderDiscountMode  = DiscountMode.percent;
    _items.clear();
    _errorMessage       = null;
  }

  /// Limpa o carrinho sem confirmar (descarta rascunho).
  Future<void> clear() async {
    if (hasItems && !_isEditingExisting) {
      try {
        await _repo.cancelOrder(_orderId);
      } catch (e) {
        debugPrint('[CartNotifier] Erro ao cancelar pedido (pode estar sincronizado ou DB travado): $e');
      }
    }
    _reset();
    notifyListeners();
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    super.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Helper: produto com preço sobreescrito pela tabela de preço do cliente
// ─────────────────────────────────────────────────────────────────────────

/// Produto cuja [price] foi substituída pelo valor da tabela de preço
/// do cliente ([PriceService.resolvePrice]).
///
/// Mantém todos os outros campos do produto original (descontos, estoque, etc.)
/// Herda [Product] apenas via composición para não quebrar [CartItem] existente.
class _ProductWithOverriddenPrice extends Product {
  _ProductWithOverriddenPrice(Product base, double tablePrice)
      : super(
          code:        base.code,
          name:        base.name,
          nameShort:   base.nameShort,
          price:       tablePrice,   // ← preço da tabela de preço
          priceMin:    base.priceMin,
          priceCost:   base.priceCost,
          stock:       base.stock,
          unit:        base.unit,
          brand:       base.brand,
          barCode:     base.barCode,
          reference:   base.reference,
          maxDiscount: base.maxDiscount,
          category:    base.category,
          lastSyncedAt: base.lastSyncedAt,
        );
}

// ─────────────────────────────────────────────────────────────────────────────
// CloneResult — Resultado de operação de clonagem de pedido
// ─────────────────────────────────────────────────────────────────────────────

class CloneResult {
  final List<String> outOfStockProducts;
  final List<String> missingProducts;

  CloneResult({
    required this.outOfStockProducts,
    required this.missingProducts,
  });

  bool get hasWarnings => outOfStockProducts.isNotEmpty || missingProducts.isNotEmpty;
}

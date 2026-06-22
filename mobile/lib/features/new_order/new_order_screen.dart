/// NewOrderScreen — Formulário para criação de novo pedido.
///
/// Layout baseado no app de referência:
/// - Cabeçalho: Cliente, Data/Hora, Forma de Pagamento, Prazo, Observação
/// - Lista de itens adicionados
/// - FAB (+) para abrir ProductPickerScreen
/// - Botões: Salvar Orçamento / Salvar Pedido
library;

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';
import '../../core/cart/cart_notifier.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_typography.dart';
import '../../core/services/company_settings_service.dart';
import '../../core/repositories/models/models.dart';
import '../../core/repositories/models/payment_species.dart';
import '../../core/repositories/models/payment_condition.dart';
import '../../core/repositories/models/natureza_operacao.dart';
import '../../core/services/discount_service.dart';
import '../customer_search/customer_search_screen.dart';
import 'product_picker_screen.dart';
import 'new_order_controller.dart';

class NewOrderScreen extends StatefulWidget {
  final CartNotifier cart;

  const NewOrderScreen({super.key, required this.cart});

  @override
  State<NewOrderScreen> createState() => _NewOrderScreenState();
}

class _NewOrderScreenState extends State<NewOrderScreen>
    with SingleTickerProviderStateMixin {
  // ── Controller (Rule-06 Clean Architecture) ─────────────────────────────
  late final NewOrderController _ctrl;

  final _currencyFmt = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final _dateFmt     = DateFormat("dd 'de' MMMM 'de' yyyy", 'pt_BR');
  final _timeFmt     = DateFormat('HH:mm', 'pt_BR');

  final TextEditingController _prazoCtrl = TextEditingController();
  final TextEditingController _obsCtrl   = TextEditingController();

  // Getters de conveniência para compatibilidade com build() sem alterar a UI.
  List<PaymentSpecies>  get _paymentOptions    => _ctrl.paymentOptions;
  PaymentSpecies?       get _selectedPayment   => _ctrl.selectedPayment;
  List<PaymentCondition> get _conditionOptions => _ctrl.conditionOptions;
  PaymentCondition?     get _selectedCondition => _ctrl.selectedCondition;
  List<NaturezaOperacao> get _naturezas        => _ctrl.naturezas;
  NaturezaOperacao?     get _selectedNatureza  => _ctrl.selectedNatureza;
  List<Map<String, dynamic>> get _priceTables  => _ctrl.priceTables;
  Map<String, dynamic>? get _selectedPriceTable => _ctrl.selectedPriceTable;
  List<PaymentCondition> get _filteredConditions => _ctrl.filteredConditions;
  bool get _loading => _ctrl.isLoading;
  bool get _saving  => _ctrl.isSaving;

  late final AnimationController _pulseCtrl;
  late final Animation<double>  _pulseAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = NewOrderController(cart: widget.cart)
      ..addListener(() { if (mounted) setState(() {}); })
      ..loadOptions();
    _obsCtrl.text = widget.cart.notes ?? '';

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.35).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _pulseCtrl.dispose();
    _prazoCtrl.dispose();
    _obsCtrl.dispose();
    super.dispose();
  }

  // _loadOptions() foi migrada para NewOrderController.loadOptions().
  // Mantida como proxy para compatibilidade com referências internas.


  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _selectCustomer() async {
    final customer = await CustomerSearchScreen.show(context);
    if (customer != null && mounted) {
      await widget.cart.setCustomer(
        id:           customer.id,
        name:         customer.name,
        priceTableId: customer.priceTableId,
      );
      setState(() {});
    }
  }

  void _selectPayment(PaymentSpecies? species) => _ctrl.selectPayment(species);



  void _selectCondition(PaymentCondition? condition) =>
      _ctrl.selectCondition(condition);

  void _selectNatureza(NaturezaOperacao? natureza) =>
      _ctrl.selectNatureza(natureza);

  Future<void> _openProductPicker() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProductPickerScreen(
          cart: widget.cart,
          customerId: widget.cart.customerId,
        ),
      ),
    );
    if (mounted) setState(() {}); // Refresh items list
  }

  Future<void> _saveOrder({bool isDraft = false}) async {
    final error = await _ctrl.saveOrder(
      prazo:   _prazoCtrl.text.trim(),
      obs:     _obsCtrl.text.trim(),
      isDraft: isDraft,
    );

    if (!mounted) return;

    if (error != null) {
      _showError(error);
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(
              isDraft ? 'Orçamento salvo!' : 'Pedido salvo com sucesso!',
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
        backgroundColor: isDraft ? AppColors.warning : AppColors.success,
        behavior: SnackBarBehavior.floating,
      ),
    );

    Navigator.of(context).pop(true);
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final items = widget.cart.items;

    return Scaffold(
      appBar: AppBar(
        title: const Text('PEDIDO'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // ── Form fields (scrollable) ──────────────────────────────
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(0),
                    children: [
                      // ── Cliente ──────────────────────────────────────────
                      _FormField(
                        label: 'Cliente',
                        required: true,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    widget.cart.customerName.isEmpty
                                        ? 'Selecione um cliente'
                                        : widget.cart.customerName,
                                    style: widget.cart.customerName.isEmpty
                                        ? AppTypography.body.copyWith(
                                            color: AppColors.textTertiary)
                                        : AppTypography.bodyBold,
                                  ),
                                ),
                                FilledButton(
                                  onPressed: _selectCustomer,
                                  child: const Text('PROCURAR'),
                                ),
                              ],
                            ),
                            // Badge/Dropdown de tabela de preço
                            // Modo none: oculto | Modo product: badge
                            // Modo prompt: dropdown de seleção manual
                            ListenableBuilder(
                              listenable: widget.cart,
                              builder: (_, __) {
                                final settings = GetIt.I.isRegistered<CompanySettingsService>()
                                    ? GetIt.I<CompanySettingsService>()
                                    : null;
                                final mode = settings?.priceTableMode ?? 'product';

                                // modo none: oculta tudo
                                if (mode == 'none') return const SizedBox.shrink();

                                // modo prompt: dropdown de seleção manual de tabela
                                if (mode == 'prompt' && _priceTables.isNotEmpty) {
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            const Icon(Icons.price_change_outlined,
                                                size: 14, color: Color(0xFF6A1B9A)),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: DropdownButtonHideUnderline(
                                                child: DropdownButton<String>(
                                                  value: _selectedPriceTable?['id']?.toString(),
                                                  isExpanded: true,
                                                  hint: Text(
                                                    'Selecione a tabela de preço',
                                                    style: AppTypography.caption.copyWith(
                                                        color: const Color(0xFF6A1B9A)),
                                                  ),
                                                  items: [
                                                    DropdownMenuItem<String>(
                                                      value: null,
                                                      child: Text('Preço base',
                                                          style: AppTypography.caption),
                                                    ),
                                                    ..._priceTables.map((t) =>
                                                      DropdownMenuItem<String>(
                                                        value: t['id']?.toString(),
                                                        child: Text(
                                                          t['name']?.toString() ?? '',
                                                          style: AppTypography.caption,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                  onChanged: (selectedId) {
                                                    final selected = _priceTables.where((t) => t['id']?.toString() == selectedId).firstOrNull;
                                                    _ctrl.selectPriceTable(selected);
                                                  },
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        // Chip indicando a tabela ativa
                                        const SizedBox(height: 4),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: _selectedPriceTable == null
                                                ? const Color(0xFFF3F3F3)
                                                : const Color(0xFFEDE7F6),
                                            borderRadius: BorderRadius.circular(20),
                                            border: Border.all(
                                              color: _selectedPriceTable == null
                                                  ? const Color(0xFFBBBBBB)
                                                  : const Color(0xFF6A1B9A),
                                              width: 1,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                _selectedPriceTable == null
                                                    ? Icons.label_outline
                                                    : Icons.label,
                                                size: 13,
                                                color: _selectedPriceTable == null
                                                    ? const Color(0xFF888888)
                                                    : const Color(0xFF6A1B9A),
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                _selectedPriceTable == null
                                                    ? 'Preço base'
                                                    : _selectedPriceTable!['name']
                                                            ?.toString() ??
                                                        '',
                                                style: AppTypography.caption.copyWith(
                                                  color: _selectedPriceTable == null
                                                      ? const Color(0xFF888888)
                                                      : const Color(0xFF6A1B9A),
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }

                                // modo product: badge da tabela do cliente
                                final tableName = widget.cart.activeTableName;
                                if (tableName == null) return const SizedBox.shrink();
                                return Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.price_change_outlined,
                                          size: 14, color: Color(0xFF2E7D32)),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Tabela: $tableName',
                                        style: AppTypography.badge.copyWith(
                                          color: const Color(0xFF2E7D32),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),

                      // ── Data + Hora (compact, one row) ──────────────────
                      _FormField(
                        label: 'Data',
                        required: true,
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _dateFmt.format(now),
                                style: AppTypography.body
                                    .copyWith(color: AppColors.textSecondary),
                              ),
                            ),
                            Text(
                              _timeFmt.format(now),
                              style: AppTypography.body
                                  .copyWith(color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),

                      // ── Espécie de Pagamento ──────────────────────────────
                      _FormField(
                        label: 'Espécie de Pagamento',
                        required: true,
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<PaymentSpecies>(
                            value: _selectedPayment,
                            isExpanded: true,
                            hint: Text(
                              'Selecione (Ex: Dinheiro / Boleto)',
                              style: AppTypography.body
                                  .copyWith(color: AppColors.textTertiary),
                            ),
                            items: _paymentOptions
                                .map((s) => DropdownMenuItem(
                                      value: s,
                                      child: Text(s.displayName,
                                          style: AppTypography.body),
                                    ))
                                .toList(),
                            onChanged: _selectPayment,
                          ),
                        ),
                      ),

                      // ── Condição de Pagamento (filtrada pela espécie) ───────
                      _FormField(
                        label: 'Condição de Pagamento',
                        required: true,
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<PaymentCondition>(
                            value: _filteredConditions.contains(_selectedCondition)
                                ? _selectedCondition
                                : null,
                            isExpanded: true,
                            hint: Text(
                              _selectedPayment == null
                                  ? 'Selecione a espécie primeiro'
                                  : (_filteredConditions.isEmpty
                                      ? 'Nenhuma condição para esta espécie'
                                      : 'Selecione o Parcelamento'),
                              style: AppTypography.body
                                  .copyWith(color: AppColors.textTertiary),
                            ),
                            items: _filteredConditions
                                .map((c) => DropdownMenuItem(
                                      value: c,
                                      child: Text(c.descricao,
                                          style: AppTypography.body),
                                    ))
                                .toList(),
                            onChanged: _selectedPayment == null ? null : _selectCondition,
                          ),
                        ),
                      ),

                      // ── Natureza de Operação (sempre visível, obrigatória) ─────
                      _FormField(
                        label: 'Natureza de Operação',
                        required: true,
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<NaturezaOperacao?>(
                            value: _selectedNatureza,
                            isExpanded: true,
                            hint: Text(
                              _naturezas.isEmpty
                                  ? 'Sincronize o app para carregar'
                                  : 'Selecione a natureza',
                              style: AppTypography.body
                                  .copyWith(color: AppColors.textTertiary),
                            ),
                            items: [
                              ..._naturezas.map((n) => DropdownMenuItem<NaturezaOperacao?>(
                                    value: n,
                                    child: Text(n.displayName,
                                        style: AppTypography.body),
                                  )),
                            ],
                            onChanged: _naturezas.isEmpty ? null : _selectNatureza,
                          ),
                        ),
                      ),

                      // ── Itens do pedido ───────────────────────────────────
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(16, 16, 12, 8),
                        decoration: const BoxDecoration(
                          border: Border(
                            top: BorderSide(color: AppColors.border),
                          ),
                        ),
                        child: Row(
                          children: [
                            Text(
                              'Itens do pedido',
                              style: AppTypography.headingMedium,
                            ),
                            if (items.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryLight.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '${items.length}',
                                    style: AppTypography.badge.copyWith(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            const Spacer(),
                            FilledButton.icon(
                              onPressed: _openProductPicker,
                              icon: ScaleTransition(
                                scale: _pulseAnim,
                                child: const Icon(Icons.add_rounded, size: 18),
                              ),
                              label: const Text('Adicionar'),
                            ),
                          ],
                        ),
                      ),

                      if (items.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          child: InkWell(
                            onTap: _openProductPicker,
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceSecondary,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppColors.primary.withOpacity(0.3),
                                  width: 1.5,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Container(
                                    width: 56,
                                    height: 56,
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withOpacity(0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.shopping_bag_outlined,
                                      color: AppColors.primary,
                                      size: 28,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Adicione produtos ao pedido',
                                    style: AppTypography.bodyBold.copyWith(
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Toque aqui para buscar no catálogo',
                                    style: AppTypography.badge.copyWith(
                                      color: AppColors.textTertiary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                      else
                        ...items.map((item) => _OrderItemTile(
                              item: item,
                              currency: _currencyFmt,
                              onRemove: () {
                                widget.cart.removeItem(item.product.code);
                                setState(() {});
                              },
                              onQuantityChanged: (newQty) {
                                widget.cart.updateQuantity(item.product.code, newQty);
                                setState(() {});
                              },
                              onDiscountChanged: (value, mode) async {
                                final result = await widget.cart.updateDiscount(
                                  item.product.code, value, mode: mode,
                                );
                                setState(() {});
                                // Avisa o vendedor se o desconto foi limitado
                                if (result.wasClamped && mounted) {
                                  final reason = result.clampReason
                                      ?? 'Desconto limitado ao máximo permitido';
                                  ScaffoldMessenger.of(context)
                                    ..hideCurrentSnackBar()
                                    ..showSnackBar(SnackBar(
                                      content: Row(
                                        children: [
                                          const Icon(Icons.warning_amber_rounded,
                                              color: Colors.white, size: 20),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              '⚠ Desconto limitado: $reason',
                                              style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w500),
                                            ),
                                          ),
                                        ],
                                      ),
                                      backgroundColor: AppColors.error,
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(10)),
                                      margin: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 8),
                                      duration: const Duration(seconds: 4),
                                    ));
                                }
                              },
                            )),

                      // ── Prazo de Entrega ────────────────────────────────
                      _FormField(
                        label: 'Prazo de entrega',
                        child: TextField(
                          controller: _prazoCtrl,
                          style: AppTypography.body,
                          decoration: const InputDecoration(
                            hintText: 'Ex: 5 dias úteis',
                          ),
                        ),
                      ),

                      // ── Observação ──────────────────────────────────────
                      _FormField(
                        label: 'Observação',
                        child: TextField(
                          controller: _obsCtrl,
                          style: AppTypography.body,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            hintText: 'Observações do pedido',
                          ),
                        ),
                      ),

                      const SizedBox(height: 80), // Space for bottom bar
                    ],
                  ),
                ),

                // ── Bottom bar: total dinâmico + buttons ─────────────────
                ListenableBuilder(
                  listenable: widget.cart,
                  builder: (_, __) {
                    final cart           = widget.cart;
                    final itemsSubtotal  = cart.items.fold(0.0, (s, i) => s + i.product.price * i.quantity);
                    final itemDiscVal    = cart.totalDiscountValue;
                    final orderDiscVal   = cart.orderDiscountValue;
                    final grandTotal     = cart.grandTotal;
                    final hasItemDisc    = itemDiscVal > 0;
                    final hasOrderDisc   = orderDiscVal > 0;
                    final cur            = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

                    return Container(
                      decoration: const BoxDecoration(
                        color: AppColors.surface,
                        border: Border(top: BorderSide(color: AppColors.border)),
                      ),
                      child: SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // ── Totalizador ───────────────────────────────────
                              if (cart.hasItems) ...[
                                // Subtotal bruto
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('Subtotal',
                                        style: AppTypography.badge.copyWith(color: AppColors.textSecondary)),
                                    Text(cur.format(itemsSubtotal),
                                        style: AppTypography.badge.copyWith(color: AppColors.textSecondary)),
                                  ],
                                ),
                                // Desconto por itens
                                if (hasItemDisc) ...[
                                  const SizedBox(height: 2),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('Desc. Itens',
                                          style: AppTypography.badge.copyWith(color: AppColors.error)),
                                      Text('- ${cur.format(itemDiscVal)}',
                                          style: AppTypography.badge.copyWith(color: AppColors.error)),
                                    ],
                                  ),
                                ],
                                // ── Desconto do pedido (global) ──────────────
                                const SizedBox(height: 6),
                                _OrderDiscountRow(
                                  cart: cart,
                                  currency: cur,
                                ),
                                if (hasOrderDisc) ...[
                                  const SizedBox(height: 2),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('Desc. Pedido',
                                          style: AppTypography.badge.copyWith(
                                            color: AppColors.error, fontWeight: FontWeight.w600)),
                                      Text('- ${cur.format(orderDiscVal)}',
                                          style: AppTypography.badge.copyWith(
                                            color: AppColors.error, fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                ],
                                const Divider(height: 12),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('Total',
                                        style: AppTypography.bodyBold.copyWith(color: AppColors.textPrimary)),
                                    Text(cur.format(grandTotal),
                                        style: AppTypography.priceLarge.copyWith(fontSize: 18,
                                            color: AppColors.actionPrimary)),
                                  ],
                                ),
                                const SizedBox(height: 10),
                              ],

                              // ── Botões ────────────────────────────────────────
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: _saving
                                          ? null
                                          : () => _saveOrder(isDraft: true),
                                      child: const Text('SALVAR ORÇAMENTO'),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: FilledButton(
                                      onPressed: _saving
                                          ? null
                                          : () => _saveOrder(),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: AppColors.success,
                                      ),
                                      child: _saving
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            )
                                          : const Text('SALVAR PEDIDO'),
                                    ),
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

              ],
            ),

    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _FormField — Wrapper for each form section
// ─────────────────────────────────────────────────────────────────────────────

class _FormField extends StatelessWidget {
  final String label;
  final bool required;
  final Widget child;

  const _FormField({
    required this.label,
    this.required = false,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.border),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RichText(
            text: TextSpan(
              text: label,
              style: AppTypography.label.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
              children: [
                if (required)
                  TextSpan(
                    text: ' *',
                    style: AppTypography.label.copyWith(
                      color: AppColors.error,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _OrderDiscountRow — Desconto global do pedido (% ou R$)
// ─────────────────────────────────────────────────────────────────────────────

class _OrderDiscountRow extends StatefulWidget {
  final CartNotifier cart;
  final NumberFormat currency;
  const _OrderDiscountRow({required this.cart, required this.currency});

  @override
  State<_OrderDiscountRow> createState() => _OrderDiscountRowState();
}

class _OrderDiscountRowState extends State<_OrderDiscountRow> {
  late final TextEditingController _pctCtrl;
  late final TextEditingController _valCtrl;

  @override
  void initState() {
    super.initState();
    final c = widget.cart;
    _pctCtrl = TextEditingController(
      text: c.orderDiscountMode == DiscountMode.percent && c.orderDiscountInput > 0
          ? _fmt(c.orderDiscountInput)
          : '',
    );
    _valCtrl = TextEditingController(
      text: c.orderDiscountMode == DiscountMode.value && c.orderDiscountInput > 0
          ? c.orderDiscountInput.toStringAsFixed(2)
          : '',
    );
  }

  String _fmt(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  @override
  void dispose() {
    _pctCtrl.dispose();
    _valCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // % Desconto do pedido
        Expanded(
          child: TextField(
            controller: _pctCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: AppTypography.body.copyWith(fontSize: 13),
            decoration: InputDecoration(
              labelText: '% Desc. Pedido',
              labelStyle: AppTypography.caption.copyWith(
                color: AppColors.textTertiary, fontSize: 11,
              ),
              suffixText: '%',
              suffixStyle: AppTypography.caption.copyWith(color: AppColors.textTertiary),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
              ),
            ),
            onChanged: (v) {
              final val = double.tryParse(v) ?? 0;
              widget.cart.setOrderDiscount(val, mode: DiscountMode.percent);
              final itemsTotal = widget.cart.items.fold(0.0, (s, i) => s + i.totalPrice);
              if (val > 0) {
                _valCtrl.text = (itemsTotal * val / 100).toStringAsFixed(2);
              } else {
                _valCtrl.text = '';
              }
            },
          ),
        ),
        const SizedBox(width: 10),
        // Valor R$ Desconto do pedido
        Expanded(
          child: TextField(
            controller: _valCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: AppTypography.body.copyWith(fontSize: 13),
            decoration: InputDecoration(
              labelText: 'R\$ Desc. Pedido',
              labelStyle: AppTypography.caption.copyWith(
                color: AppColors.textTertiary, fontSize: 11,
              ),
              prefixText: 'R\$ ',
              prefixStyle: AppTypography.caption.copyWith(color: AppColors.textTertiary),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
              ),
            ),
            onChanged: (v) {
              final val = double.tryParse(v) ?? 0;
              widget.cart.setOrderDiscount(val, mode: DiscountMode.value);
              final itemsTotal = widget.cart.items.fold(0.0, (s, i) => s + i.totalPrice);
              if (val > 0 && itemsTotal > 0) {
                _pctCtrl.text = (val / itemsTotal * 100).toStringAsFixed(1);
              } else {
                _pctCtrl.text = '';
              }
            },
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _OrderItemTile — Shows an item in the order with quantity, discount, delete
// ─────────────────────────────────────────────────────────────────────────────

class _OrderItemTile extends StatefulWidget {
  final CartItem item;
  final NumberFormat currency;
  final VoidCallback onRemove;
  final ValueChanged<double> onQuantityChanged;
  final Future<void> Function(double value, DiscountMode mode) onDiscountChanged;

  const _OrderItemTile({
    required this.item,
    required this.currency,
    required this.onRemove,
    required this.onQuantityChanged,
    required this.onDiscountChanged,
  });

  @override
  State<_OrderItemTile> createState() => _OrderItemTileState();
}

class _OrderItemTileState extends State<_OrderItemTile> {
  late final TextEditingController _pctCtrl;
  late final TextEditingController _valCtrl;
  bool _showDiscount = false;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _showDiscount = item.discount > 0;
    _pctCtrl = TextEditingController(
      text: item.discountMode == DiscountMode.percent && item.rawDiscountInput > 0
          ? _fmtNum(item.rawDiscountInput)
          : '',
    );
    _valCtrl = TextEditingController(
      text: item.discountMode == DiscountMode.value && item.rawDiscountInput > 0
          ? item.rawDiscountInput.toStringAsFixed(2)
          : '',
    );
  }

  String _fmtNum(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  @override
  void dispose() {
    _pctCtrl.dispose();
    _valCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final qty = _fmtNum(item.quantity);

    return Dismissible(
      key: ValueKey(item.product.code),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: AppColors.error,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => widget.onRemove(),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AppColors.border, width: 0.5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Linha 1: Nome + preço + X ──────────────────────────────
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.product.name,
                    style: AppTypography.body,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      widget.currency.format(item.totalPrice),
                      style: AppTypography.bodyBold,
                    ),
                    if (item.discount > 0)
                      Text(
                        '-${widget.currency.format(item.discountValue)}',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.error, fontSize: 11,
                        ),
                      ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  color: AppColors.textTertiary,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  tooltip: 'Remover item',
                  onPressed: widget.onRemove,
                ),
              ],
            ),

            // ── Linha 2: unit price | desc badge | qty stepper ────────
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$qty x ${widget.currency.format(item.product.price)}',
                    style: AppTypography.caption
                        .copyWith(color: AppColors.textSecondary),
                  ),
                ),

                // Discount badge/toggle
                InkWell(
                  onTap: () => setState(() => _showDiscount = !_showDiscount),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: item.discount > 0
                          ? AppColors.error.withOpacity(0.1)
                          : AppColors.surfaceSecondary,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: item.discount > 0
                            ? AppColors.error.withOpacity(0.3)
                            : AppColors.border,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.local_offer_outlined, size: 14,
                          color: item.discount > 0
                              ? AppColors.error : AppColors.textTertiary),
                        const SizedBox(width: 4),
                        Text(
                          item.discount > 0
                              ? (item.discountMode == DiscountMode.value
                                  ? '-R\$ ${item.discountValue.toStringAsFixed(2)}'
                                  : '${item.discount.toStringAsFixed(1)}%')
                              : 'Desc',
                          style: AppTypography.caption.copyWith(
                            color: item.discount > 0
                                ? AppColors.error : AppColors.textTertiary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Qty stepper
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceSecondary,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _StepperButton(
                        icon: Icons.remove,
                        onTap: item.quantity > 1
                            ? () => widget.onQuantityChanged(item.quantity - 1)
                            : null,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text(qty,
                            style: AppTypography.bodyBold.copyWith(fontSize: 14)),
                      ),
                      _StepperButton(
                        icon: Icons.add,
                        onTap: () => widget.onQuantityChanged(item.quantity + 1),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // ── Linha 3: Desconto expandível ──────────────────────────
            if (_showDiscount)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    // % Desconto
                    Expanded(
                      child: _discountField(
                        controller: _pctCtrl,
                        label: '% Desconto',
                        suffix: '%',
                        onChanged: (v) {
                          final val = double.tryParse(v) ?? 0;
                          widget.onDiscountChanged(val, DiscountMode.percent);
                          // Espelha R$ usando o subtotal (price × qty) como base
                          final subtotal = item.product.price * item.quantity;
                          if (val > 0) {
                            _valCtrl.text = (subtotal * val / 100)
                                .toStringAsFixed(2);
                          } else {
                            _valCtrl.text = '';
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Valor Desconto
                    Expanded(
                      child: _discountField(
                        controller: _valCtrl,
                        label: 'Valor Desc',
                        prefix: 'R\$ ',
                        onChanged: (v) {
                          final val = double.tryParse(v.replaceAll(',', '.')) ?? 0;
                          widget.onDiscountChanged(val, DiscountMode.value);
                          // Espelha o % usando o subtotal (price × qty) como base
                          final subtotal = item.product.price * item.quantity;
                          if (val > 0 && subtotal > 0) {
                            _pctCtrl.text = (val / subtotal * 100)
                                .toStringAsFixed(2)
                                .replaceAll(RegExp(r'\.?0+$'), '');
                          } else {
                            _pctCtrl.text = '';
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _discountField({
    required TextEditingController controller,
    required String label,
    String? suffix,
    String? prefix,
    required ValueChanged<String> onChanged,
  }) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: AppTypography.body.copyWith(fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: AppTypography.caption.copyWith(
          color: AppColors.textTertiary, fontSize: 11,
        ),
        suffixText: suffix,
        prefixText: prefix,
        suffixStyle: AppTypography.caption.copyWith(color: AppColors.textTertiary),
        prefixStyle: AppTypography.caption.copyWith(color: AppColors.textTertiary),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
      onChanged: onChanged,
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────────
// _StepperButton
// ───────────────────────────────────────────────────────────────────────────────

class _StepperButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _StepperButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: enabled
              ? AppColors.primary.withOpacity(0.1)
              : AppColors.surfaceMuted,
        ),
        child: Icon(
          icon,
          size: 16,
          color: enabled ? AppColors.primary : AppColors.textDisabled,
        ),
      ),
    );
  }
}


/// CartScreen — Tela do carrinho de compras.
///
/// UX FIELD RULES:
/// - Swipe to remove com undo de 3s (snackbar persistente com botão "Desfazer")
/// - Edição de quantidade inline com validação (mínimo = 1)
/// - Totalizador sempre visível no rodapé (não scrollável)
/// - Botão "Confirmar Pedido" só habilitado com itens > 0
/// - Nenhuma ação destrutiva sem chance de desfazer
library;

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';
import '../../../core/cart/cart_notifier.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_typography.dart';
import '../../../core/repositories/models/models.dart';
import '../../../core/repositories/models/seller.dart';
import '../../../core/services/discount_service.dart';
import '../../../core/session/session_service.dart';
import '../order_confirm/order_confirm_screen.dart';

class CartScreen extends StatefulWidget {
  final CartNotifier cart;

  const CartScreen({super.key, required this.cart});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final _currencyFmt = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final _notesCtrl = TextEditingController();

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Ações
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _removeItem(CartItem item) async {
    final product = item.product;

    // Remove item
    await widget.cart.removeItem(product.code);
    if (!mounted) return;

    // Snackbar com undo de 3s
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '${product.name} removido do carrinho',
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: AppColors.textPrimary,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Desfazer',
          textColor: AppColors.actionPrimaryDark,
          onPressed: () async {
            await widget.cart.addProduct(product, quantity: item.quantity);
          },
        ),
      ),
    );
  }

  Future<void> _updateQty(CartItem item, double qty) async {
    await widget.cart.updateQuantity(item.product.code, qty);
  }

  void _goToConfirm() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OrderConfirmScreen(cart: widget.cart),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.cart,
      builder: (ctx, _) {
        final items = widget.cart.items;

        return Column(
          children: [
            // ── Lista de itens ────────────────────────────────────────
            Expanded(
              child: items.isEmpty
                  ? _buildEmptyCart()
                  : ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (_, i) => _CartItemRow(
                        item:       items[i],
                        currency:   _currencyFmt,
                        onRemove:   () => _removeItem(items[i]),
                        onQtyMinus: () => _updateQty(items[i], items[i].quantity - 1),
                        onQtyPlus:  () => _updateQty(items[i], items[i].quantity + 1),
                        onDiscount: (val, mode) {
                          final session = GetIt.I<SessionService>();
                          final sellerForDiscount = session.sellerMaxDiscount != null
                              ? Seller(
                                  id:          session.sellerId,
                                  name:        session.activeSession!.sellerName,
                                  maxDiscount: session.sellerMaxDiscount,
                                )
                              : null;
                          return widget.cart.updateDiscount(
                            items[i].product.code,
                            val,
                            mode:   mode,
                            seller: sellerForDiscount,
                          );
                        },
                      ),
                    ),
            ),

            // ── Campo de observações ──────────────────────────────────
            if (items.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  controller: _notesCtrl,
                  onChanged: widget.cart.setNotes,
                  maxLines: 2,
                  style: AppTypography.body,
                  decoration: const InputDecoration(
                    hintText: 'Observações do pedido (opcional)',
                    prefixIcon: Icon(Icons.notes_rounded),
                  ),
                ),
              ),

            // ── Rodapé: total + botão confirmar ───────────────────────
            _CartFooter(
              total:    widget.cart.total,
              hasItems: widget.cart.hasItems,
              currency: _currencyFmt,
              onConfirm: _goToConfirm,
            ),
          ],
        );
      },
    );
  }

  Widget _buildEmptyCart() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.shopping_cart_outlined, size: 64, color: AppColors.textTertiary),
          const SizedBox(height: 16),
          Text(
            'Carrinho vazio',
            style: AppTypography.cardTitle.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Text(
            'Vá ao catálogo e adicione produtos',
            style: AppTypography.body.copyWith(color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _CartItemRow
// _____________________________________________________________________________

class _CartItemRow extends StatefulWidget {
  final CartItem   item;
  final NumberFormat currency;
  final VoidCallback onRemove;
  final VoidCallback onQtyMinus;
  final VoidCallback onQtyPlus;
  /// Callback com (valor, modo) para aplicar desconto via CartNotifier.
  final Future<void> Function(double value, DiscountMode mode) onDiscount;

  const _CartItemRow({
    required this.item,
    required this.currency,
    required this.onRemove,
    required this.onQtyMinus,
    required this.onQtyPlus,
    required this.onDiscount,
  });

  @override
  State<_CartItemRow> createState() => _CartItemRowState();
}

class _CartItemRowState extends State<_CartItemRow> {
  bool _showDiscount = false;
  /// Modo atual: percentual ou valor fixo.
  DiscountMode _mode = DiscountMode.percent;
  late final TextEditingController _discountCtrl;

  @override
  void initState() {
    super.initState();
    // Restaura modo e valor bruto do item se já tem desconto
    _mode = widget.item.discountMode;
    final raw = widget.item.rawDiscountInput;
    _discountCtrl = TextEditingController(
      text: raw > 0 ? raw.toStringAsFixed(_mode == DiscountMode.percent ? 0 : 2) : '',
    );
  }

  @override
  void dispose() {
    _discountCtrl.dispose();
    super.dispose();
  }

  /// Calcula o máximo permitível no modo atual para exibir no helperText.
  String _maxHint() {
    final svc       = DiscountService();
    final session   = GetIt.I<SessionService>();
    // Cria Seller mínimo apenas com maxDiscount para o DiscountService
    final sellerMin = session.sellerMaxDiscount != null
        ? Seller(id: session.sellerId, name: '', maxDiscount: session.sellerMaxDiscount)
        : null;
    final maxPct = svc.maxAllowed(widget.item.product, sellerMin);
    if (_mode == DiscountMode.percent) {
      return 'Máx. ${maxPct.toStringAsFixed(0)}%';
    } else {
      final maxVal = widget.item.product.price * maxPct / 100;
      return 'Máx. R\$${maxVal.toStringAsFixed(2)}';
    }
  }

  void _applyDiscount() {
    final raw = double.tryParse(_discountCtrl.text.replaceAll(',', '.')) ?? 0;
    widget.onDiscount(raw, _mode);
    setState(() => _showDiscount = false);
  }

  @override
  Widget build(BuildContext context) {
    final item        = widget.item;
    final maxDiscount = item.product.maxDiscount ?? 0.0;
    final hasDiscount = item.discount > 0;

    return Dismissible(
      key: Key(item.product.code),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: AppColors.syncError,
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 28),
      ),
      onDismissed: (_) => widget.onRemove(),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surfacePrimary,
          border: Border(bottom: BorderSide(color: AppColors.divider)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Linha principal ───────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  // Nome e código
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.product.name, style: AppTypography.bodyBold, maxLines: 1, overflow: TextOverflow.ellipsis),
                        Row(
                          children: [
                            Text(item.product.code, style: AppTypography.productCode.copyWith(color: AppColors.textSecondary)),
                            if (hasDiscount) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: AppColors.syncSuccessLight,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: AppColors.syncSuccess),
                                ),
                                child: Text(
                                  '-${item.discount.toStringAsFixed(0)}%',
                                  style: AppTypography.badge.copyWith(color: AppColors.syncSuccess, fontSize: 10),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Controles de quantidade
                  _QtyControl(
                    quantity: item.quantity,
                    onMinus:  widget.onQtyMinus,
                    onPlus:   widget.onQtyPlus,
                  ),
                  const SizedBox(width: 8),

                  // Total + botão de desconto
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      SizedBox(
                        width: 86,
                        child: Text(
                          widget.currency.format(item.totalPrice),
                          style: AppTypography.priceNormal,
                          textAlign: TextAlign.right,
                        ),
                      ),
                      if (maxDiscount > 0)
                        GestureDetector(
                          onTap: () => setState(() => _showDiscount = !_showDiscount),
                          child: Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _showDiscount ? Icons.local_offer_rounded : Icons.local_offer_outlined,
                                  size: 13,
                                  color: hasDiscount ? AppColors.syncSuccess : AppColors.textSecondary,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  hasDiscount ? '${item.discount.toStringAsFixed(0)}% desc.' : 'Desconto',
                                  style: AppTypography.badge.copyWith(
                                    fontSize: 10,
                                    color: hasDiscount ? AppColors.syncSuccess : AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),

            // ── Row de desconto expansível ────────────────────────────
            if (_showDiscount)
              Container(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Toggle %/R$
                    SegmentedButton<DiscountMode>(
                      segments: const [
                        ButtonSegment(
                          value: DiscountMode.percent,
                          label: Text('%'),
                          icon: Icon(Icons.percent, size: 14),
                        ),
                        ButtonSegment(
                          value: DiscountMode.value,
                          label: Text('R\$'),
                          icon: Icon(Icons.attach_money, size: 14),
                        ),
                      ],
                      selected: {_mode},
                      onSelectionChanged: (s) {
                        setState(() {
                          _mode = s.first;
                          _discountCtrl.clear();
                        });
                      },
                      style: ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        textStyle: WidgetStatePropertyAll(AppTypography.badge),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _discountCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            style: AppTypography.body,
                            decoration: InputDecoration(
                              hintText: _mode == DiscountMode.percent ? 'Ex: 10' : 'Ex: 25,00',
                              suffixText: _mode == DiscountMode.percent ? '%' : 'R\$',
                              helperText: _maxHint(),
                              helperStyle: AppTypography.badge.copyWith(color: AppColors.textSecondary),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            ),
                            onSubmitted: (_) => _applyDiscount(),
                            autofocus: true,
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _applyDiscount,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.syncSuccess,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text('OK', style: TextStyle(color: Colors.white)),
                        ),
                        if (hasDiscount) ...[
                          const SizedBox(width: 6),
                          TextButton(
                            onPressed: () {
                              _discountCtrl.clear();
                              widget.onDiscount(0, _mode);
                              setState(() => _showDiscount = false);
                            },
                            style: TextButton.styleFrom(
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text(
                              'Remover',
                              style: TextStyle(color: AppColors.syncError, fontSize: 13),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}


class _QtyControl extends StatelessWidget {
  final double quantity;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  const _QtyControl({required this.quantity, required this.onMinus, required this.onPlus});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize:  MainAxisSize.min,
      children: [
        // Mínimo 48dp de touch target
        SizedBox(
          width: 40, height: 40,
          child: IconButton(
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.remove_circle_outline_rounded),
            iconSize: 26,
            color: quantity <= 1 ? AppColors.textTertiary : AppColors.syncError,
            onPressed: onMinus,
          ),
        ),
        SizedBox(
          width: 42,
          child: Text(
            quantity.toStringAsFixed(quantity % 1 == 0 ? 0 : 2),
            style: AppTypography.priceNormal.copyWith(fontSize: 17),
            textAlign: TextAlign.center,
          ),
        ),
        SizedBox(
          width: 40, height: 40,
          child: IconButton(
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.add_circle_outline_rounded),
            iconSize: 26,
            color: AppColors.actionPrimary,
            onPressed: onPlus,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _CartFooter — Totalizador fixo no rodapé
// ─────────────────────────────────────────────────────────────────────────────

class _CartFooter extends StatelessWidget {
  final double total;
  final bool hasItems;
  final NumberFormat currency;
  final VoidCallback onConfirm;

  const _CartFooter({
    required this.total,
    required this.hasItems,
    required this.currency,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surfacePrimary,
        border: Border(top: BorderSide(color: AppColors.border, width: 1.5)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Total do pedido', style: AppTypography.fieldLabel.copyWith(color: AppColors.textSecondary)),
                  Text(currency.format(total), style: AppTypography.priceLarge),
                ],
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.check_circle_outline_rounded),
                label: const Text('Revisar e Confirmar'),
                onPressed: hasItems ? onConfirm : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

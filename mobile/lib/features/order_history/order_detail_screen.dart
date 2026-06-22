/// OrderDetailScreen — Detalhes completos de um pedido/orçamento.
///
/// UX:
/// - Cabeçalho: dados do cliente, data/hora, status badge com cor
/// - Seção ERP: Nº do pedido se integrado
/// - Seção financeiro: forma de pagamento, condição, prazo, desconto, total
/// - Lista de itens: produto, qtd × preço, desconto por item
/// - Ações: Compartilhar, Reabrir como rascunho (pedido) ou Editar/Converter/Excluir (orçamento)
///
/// Navegação: push a partir do tile na OrderHistoryScreen.
library;

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:coliseu_sales/core/config/app_config_service.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/cart/cart_notifier.dart';
import '../../core/network/auto_sync_service.dart';
import '../../core/repositories/models/models.dart';
import '../../core/repositories/order_repository.dart';
import '../../core/session/session_service.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_typography.dart';
import '../new_order/new_order_screen.dart';
import '../../shared/order_share_sheet.dart';

class OrderDetailScreen extends StatefulWidget {
  final Order        order;
  final CartNotifier cart;

  const OrderDetailScreen({
    super.key,
    required this.order,
    required this.cart,
  });

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  late Order _order;
  bool _converting = false;

  @override
  void initState() {
    super.initState();
    _order = widget.order;
  }

  @override
  Widget build(BuildContext context) {
    final cur     = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final dateFmt = DateFormat("dd/MM/yyyy 'às' HH:mm", 'pt_BR');
    final dt      = DateTime.tryParse(_order.createdAt)?.toLocal() ?? DateTime.now();
    final subtotal = _order.totalAmount + _order.discountValue;

    return Scaffold(
      appBar: AppBar(
        title: Text(_order.isDraft ? 'Detalhes do Orçamento' : 'Detalhes do Pedido'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Compartilhar',
            onPressed: () => OrderShareSheet.show(context, _order),
          ),
        ],
      ),
      backgroundColor: AppColors.surfaceSecondary,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _StatusBanner(status: _order.syncStatus, erpOrderId: _order.erpOrderId),
          const SizedBox(height: 14),

          _InfoCard(title: 'Pedido', rows: [
            _Row(Icons.person_outline_rounded, 'Cliente',   _order.customerName),
            _Row(Icons.schedule_rounded,        'Data',     dateFmt.format(dt)),
            if (_order.naturezaDescricao != null)
              _Row(Icons.category_outlined, 'Natureza', _order.naturezaDescricao!),
          ]),
          const SizedBox(height: 10),

          _InfoCard(title: 'Pagamento', rows: [
            if (_order.paymentSpeciesName != null)
              _Row(Icons.payments_outlined, 'Espécie', _order.paymentSpeciesName!),
            if (_order.paymentConditionName != null)
              _Row(Icons.receipt_long_outlined, 'Condição', _order.paymentConditionName!),
          ]),
          const SizedBox(height: 10),

          _SectionLabel('Itens (${_order.items.length})'),
          ..._order.items.map((item) => _ItemTile(item: item, currency: cur)),
          const SizedBox(height: 10),

          _InfoCard(title: 'Totais', rows: [
            _Row(Icons.receipt_outlined,          'Subtotal',  cur.format(subtotal)),
            if (_order.discountValue > 0)
              _Row(Icons.local_offer_outlined, 'Desconto', '- ${cur.format(_order.discountValue)}'),
            _Row(Icons.attach_money_rounded,      'Total',     cur.format(_order.totalAmount)),
          ]),
          const SizedBox(height: 24),

          // ── Ações ─────────────────────────────────────────────────────
          if (_order.isDraft) ...[
            FilledButton.icon(
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Editar Orçamento'),
              onPressed: () => _editQuote(context),
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              icon: _converting
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.check_circle_outline_rounded),
              label: const Text('Converter em Pedido'),
              onPressed: _converting ? null : () => _convertToOrder(context),
              style: FilledButton.styleFrom(backgroundColor: AppColors.success),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('Excluir Orçamento'),
              onPressed: () => _deleteQuote(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: const BorderSide(color: AppColors.error),
              ),
            ),
          ] else if (_order.syncStatus == OrderSyncStatus.pending || _order.syncStatus == OrderSyncStatus.error) ...[
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.actionPrimary, // Cor azul forte do print
                minimumSize: const Size.fromHeight(50),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                   Icon(Icons.edit_outlined),
                   SizedBox(width: 8),
                   Text('Reabrir como Rascunho'),
                ]
              ),
              onPressed: () => _reopenAsDraft(context),
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  /// Abre o orçamento para edição no formulário.
  Future<void> _editQuote(BuildContext context) async {
    await widget.cart.loadFromOrder(_order);
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => NewOrderScreen(cart: widget.cart)),
    );
  }

  /// Converte orçamento em pedido real e enfileira para sync.
  Future<void> _convertToOrder(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Converter em Pedido?'),
        content: const Text(
          'O orçamento será convertido em pedido e enviado para integração com o ERP. '
          'Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Converter'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _converting = true);
    try {
      final repo    = GetIt.I<OrderRepository>();
      final session = GetIt.I<SessionService>().activeSession;
      if (session == null) throw StateError('Sessão expirada');

      final updated = await repo.convertQuoteToOrder(
        orderId:   _order.id,
        sellerId:  session.sellerId,
        companyId: await GetIt.I<AppConfigService>().getBranchId() ?? session.companyId,
      );

      GetIt.I<AutoSyncService>().triggerManual();

      if (!mounted) return;
      setState(() => _order = updated);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(children: [
            Icon(Icons.check_circle, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text('Pedido criado com sucesso!', style: TextStyle(color: Colors.white)),
          ]),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _converting = false);
    }
  }

  /// Exclui o orçamento do SQLite.
  Future<void> _deleteQuote(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir Orçamento?'),
        content: const Text('Este orçamento será excluído permanentemente.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    try {
      await GetIt.I<OrderRepository>().cancelOrder(_order.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Orçamento excluído'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  /// Reabre o pedido como rascunho no formulário.
  Future<void> _reopenAsDraft(BuildContext context) async {
    await widget.cart.loadFromOrder(_order);
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => NewOrderScreen(cart: widget.cart)),
    );
  }

}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _StatusBanner extends StatelessWidget {
  final OrderSyncStatus status;
  final String?         erpOrderId;

  const _StatusBanner({required this.status, this.erpOrderId});

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (status) {
      OrderSyncStatus.synced  => ('Integrado ao ERP',    AppColors.syncSuccess,    Icons.check_circle_rounded),
      OrderSyncStatus.pending => ('Pendente de envio',   AppColors.syncPending,    Icons.hourglass_empty_rounded),
      OrderSyncStatus.syncing => ('Enviando...',          AppColors.syncInProgress, Icons.sync_rounded),
      OrderSyncStatus.error   => ('Erro na integração',  AppColors.syncError,      Icons.error_outline_rounded),
      OrderSyncStatus.draft   => ('Orçamento',           const Color(0xFF7C4DFF), Icons.edit_note_rounded),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTypography.bodyBold.copyWith(color: color)),
                if (erpOrderId != null)
                  Text('ERP #$erpOrderId',
                      style: AppTypography.badge.copyWith(color: color)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String        title;
  final List<Widget>  rows;

  const _InfoCard({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfacePrimary,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Text(title,
                style: AppTypography.fieldLabel.copyWith(color: AppColors.textSecondary)),
          ),
          const Divider(height: 1, color: AppColors.divider),
          ...rows,
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
        child: Text(text,
            style: AppTypography.fieldLabel.copyWith(color: AppColors.textSecondary)),
      );
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String   label;
  final String   value;

  const _Row(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: AppColors.textSecondary),
            const SizedBox(width: 10),
            SizedBox(
              width: 80,
              child: Text(label,
                  style: AppTypography.body.copyWith(color: AppColors.textSecondary)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(value,
                  style: AppTypography.bodyBold,
                  textAlign: TextAlign.right),
            ),
          ],
        ),
      );
}

class _ItemTile extends StatelessWidget {
  final OrderItem    item;
  final NumberFormat currency;

  const _ItemTile({required this.item, required this.currency});

  @override
  Widget build(BuildContext context) {
    final qty = item.quantity == item.quantity.truncate()
        ? item.quantity.toInt().toString()
        : item.quantity.toStringAsFixed(1);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfacePrimary,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.productName,
                    style: AppTypography.bodyBold,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(
                  '$qty × ${currency.format(item.unitPrice)}'
                  '${_discountLabel(item, currency)}',
                  style: AppTypography.badge.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Text(currency.format(item.totalPrice), style: AppTypography.priceNormal),
        ],
      ),
    );
  }

  /// Formata a label de desconto respeitando o [OrderItem.discountMode].
  ///
  /// - Modo 'value': exibe o desconto como valor absoluto em R$.
  /// - Modo 'percent': exibe o percentual com até 2 casas decimais.
  String _discountLabel(OrderItem item, NumberFormat cur) {
    if (item.discount <= 0) return '';
    if (item.discountMode == 'value') {
      // Recalcula valor absoluto: unitPrice × qty − totalPrice
      final discR = item.unitPrice * item.quantity - item.totalPrice;
      return ' (-${cur.format(discR)})';
    }
    // Percentual — remove zeros desnecessários (3.00% → 3%, 2.88% → 2,88%)
    final pctStr = item.discount
        .toStringAsFixed(2)
        .replaceAll(RegExp(r'\.?0+$'), '');
    return ' (-$pctStr%)';
  }
}

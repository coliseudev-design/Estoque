/// OrderConfirmScreen — Revisão final e confirmação deliberada do pedido.
///
/// UX FIELD RULES:
/// - Espécie de Pagamento: OBRIGATÓRIA antes de confirmar
/// - Natureza de Operação: OPCIONAL (sistemas sem natureza no ERP funcionam)
/// - Desconto por item: editável nesta tela se o vendedor tiver permissão
/// - Confirmação requer gesto DELIBERADO: slide-to-confirm (não single tap)
/// - Pedido confirmado é IMUTÁVEL — nenhuma edição posterior
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:coliseu_speed/core/config/app_config_service.dart';
import 'package:intl/intl.dart';
import '../../../core/cart/cart_notifier.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_typography.dart';
import '../../../core/repositories/models/payment_species.dart';
import '../../../core/repositories/models/payment_condition.dart';
import '../../../core/repositories/models/natureza_operacao.dart';
import '../../../core/repositories/models/seller.dart';
import '../../../core/repositories/payment_species_repository.dart';
import '../../../core/repositories/payment_condition_repository.dart';
import '../../../core/repositories/natureza_operacao_repository.dart';
import '../../../core/services/discount_service.dart';
import '../../../core/session/session_service.dart';
import '../customer_search/customer_search_screen.dart';

class OrderConfirmScreen extends StatefulWidget {
  final CartNotifier cart;

  const OrderConfirmScreen({super.key, required this.cart});

  @override
  State<OrderConfirmScreen> createState() => _OrderConfirmScreenState();
}

class _OrderConfirmScreenState extends State<OrderConfirmScreen> {
  final _currencyFmt   = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  bool _confirming     = false;
  bool _loadingOptions = true;

  List<PaymentSpecies>   _species   = [];
  List<PaymentCondition> _conditions = [];
  List<NaturezaOperacao> _naturezas = [];

  @override
  void initState() {
    super.initState();
    _loadOptions();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Carregamento de opções do SQLite local
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _loadOptions() async {
    final speciesRepo   = GetIt.I<PaymentSpeciesRepository>();
    final conditionRepo = GetIt.I<PaymentConditionRepository>();
    final naturezaRepo  = GetIt.I<NaturezaOperacaoRepository>();

    final results = await Future.wait([
      speciesRepo.getAll(),
      conditionRepo.getAll(),
      naturezaRepo.getAll(),
    ]);

    if (!mounted) return;
    setState(() {
      _species    = results[0] as List<PaymentSpecies>;
      _conditions = results[1] as List<PaymentCondition>;
      _naturezas  = results[2] as List<NaturezaOperacao>;
      _loadingOptions = false;
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Confirmação
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _onConfirm() async {
    if (_confirming) return;

    // Valida: cliente obrigatório
    if (widget.cart.customerId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecione o cliente antes de confirmar o pedido.'),
          backgroundColor: AppColors.syncError,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Valida: espécie de pagamento é obrigatória
    if (widget.cart.paymentSpeciesId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecione a forma de pagamento (Espécie) antes de confirmar.'),
          backgroundColor: AppColors.syncError,
        ),
      );
      return;
    }

    if (widget.cart.paymentConditionId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecione o parcelamento (Condição) antes de confirmar.'),
          backgroundColor: AppColors.syncError,
        ),
      );
      return;
    }

    setState(() => _confirming = true);
    await HapticFeedback.heavyImpact();

    try {
      // REGRA Rule-03: sellerId e companyId SEMPRE da sessão autenticada.
      final session = GetIt.I<SessionService>();
      final config = GetIt.I<AppConfigService>();
      final companyId = await config.getBranchId() ?? session.companyId;
      await widget.cart.confirmOrder(
        sellerId:  session.sellerId,
        companyId: companyId,
      );

      if (!mounted) return;
      _showSuccessAndPop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _confirming = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao confirmar pedido: $e'),
          backgroundColor: AppColors.syncError,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Painel de desconto
  // ─────────────────────────────────────────────────────────────────────────

  /// Constr\u00f3i o painel de resumo de desconto usando [DiscountService.summarize()].
  Widget _buildDiscountSummary() {
    final svc     = DiscountService();
    final session = GetIt.I<SessionService>();
    final sellerMin = session.sellerMaxDiscount != null
        ? Seller(id: session.sellerId, name: '', maxDiscount: session.sellerMaxDiscount)
        : null;

    final summary = svc.summarize(
      items:  widget.cart.items,
      seller: sellerMin,
    );

    if (!summary.hasDiscounts) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.syncSuccessLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.syncSuccess),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Título
          Row(
            children: [
              const Icon(Icons.local_offer_rounded, size: 16, color: AppColors.syncSuccess),
              const SizedBox(width: 6),
              Text(
                'Resumo de Descontos',
                style: AppTypography.badge.copyWith(
                  color: AppColors.syncSuccess,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Linha por item com desconto
          for (final i in summary.items.where((i) => i.hasDiscount))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      i.item.product.name,
                      style: AppTypography.badge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Preço tabela riscado
                  Text(
                    _currencyFmt.format(i.item.product.price),
                    style: AppTypography.badge.copyWith(
                      decoration: TextDecoration.lineThrough,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_right_rounded, size: 14, color: AppColors.textSecondary),
                  // Badge de desconto
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: i.hasMarginalAlert ? AppColors.syncErrorLight : AppColors.syncSuccessLight,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: i.hasMarginalAlert ? AppColors.syncError : AppColors.syncSuccess,
                      ),
                    ),
                    child: Text(
                      '-${i.result.percent.toStringAsFixed(0)}%',
                      style: AppTypography.badge.copyWith(
                        fontSize: 10,
                        color: i.hasMarginalAlert ? AppColors.syncError : AppColors.syncSuccess,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _currencyFmt.format(i.result.unitPriceAfterDiscount),
                    style: AppTypography.badge.copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (i.hasMarginalAlert) ...[
                    const SizedBox(width: 4),
                    Tooltip(
                      message: i.result.clampReason ?? '',
                      child: const Icon(Icons.info_outline, size: 12, color: AppColors.syncError),
                    ),
                  ],
                ],
              ),
            ),

          const Divider(height: 16),

          // Totalizador: bruto → desconto → líquido
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Subtotal tabela',
                  style: AppTypography.badge.copyWith(color: AppColors.textSecondary)),
              Text(_currencyFmt.format(summary.grossTotal),
                  style: AppTypography.badge.copyWith(color: AppColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Desconto total',
                  style: AppTypography.badge.copyWith(color: AppColors.syncSuccess)),
              Text(
                '-${_currencyFmt.format(summary.totalDiscountValue)} '
                '(${summary.avgDiscountPercent.toStringAsFixed(1)}%)',
                style: AppTypography.badge.copyWith(
                  color: AppColors.syncSuccess,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total com desconto', style: AppTypography.bodyBold),
              Text(_currencyFmt.format(summary.netTotal), style: AppTypography.priceLarge),
            ],
          ),

          // Aviso de itens clampados pelo sistema
          if (summary.itemsWithAlert > 0) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded, size: 14, color: AppColors.syncPending),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '${summary.itemsWithAlert} item(s) com desconto ajustado pelo sistema.',
                    style: AppTypography.badge.copyWith(color: AppColors.syncPending),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _showSuccessAndPop() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        icon: const Icon(Icons.check_circle_rounded, color: AppColors.syncSuccess, size: 56),
        title: const Text('Pedido registrado!'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Seu pedido foi salvo localmente.',
              style: AppTypography.body.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.syncPendingLight,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.syncPending),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.schedule_rounded, color: AppColors.syncPending, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    'Aguardando sincronização',
                    style: AppTypography.badge.copyWith(color: AppColors.syncPending),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(context)
                ..pop()  // fecha dialog
                ..pop(); // volta da OrderConfirmScreen
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final items    = widget.cart.items;
    final total    = widget.cart.total;
    final customer = widget.cart.customerName;
    final notes    = widget.cart.notes;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Revisar Pedido'),
      ),
      backgroundColor: AppColors.surfaceSecondary,
      body: Column(
        children: [
          // ── Resumo scrollável ────────────────────────────────────────────
          Expanded(
            child: _loadingOptions
                ? const Center(child: CircularProgressIndicator(color: AppColors.actionPrimary))
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Cliente
                        InkWell(
                          onTap: () async {
                            final selected = await CustomerSearchScreen.show(context);
                            if (selected != null && mounted) {
                              widget.cart.setCustomer(
                                id:   selected.id,
                                name: selected.name,
                              );
                              setState(() {});
                            }
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: _SectionCard(
                            title: 'Cliente',
                            child: Row(
                              children: [
                                Icon(
                                  customer.isEmpty ? Icons.person_add_alt_1_rounded : Icons.person_outline,
                                  color: customer.isEmpty ? AppColors.actionPrimary : AppColors.textSecondary,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    customer.isEmpty ? 'Toque para selecionar' : customer,
                                    style: customer.isEmpty
                                        ? AppTypography.body.copyWith(color: AppColors.actionPrimary)
                                        : AppTypography.bodyBold,
                                  ),
                                ),
                                Icon(Icons.edit_outlined, size: 18, color: AppColors.textSecondary),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // ── Espécie de Pagamento (OBRIGATÓRIO) ────────────
                        _SectionCard(
                          title: 'Espécie de Pagamento *',
                          child: _species.isEmpty
                              ? Text(
                                  'Nenhuma forma de pagamento disponível. Sincronize o catálogo.',
                                  style: AppTypography.body.copyWith(color: AppColors.syncError),
                                )
                              : _PaymentSpeciesSelector(
                                  species: _species,
                                  selectedId: widget.cart.paymentSpeciesId,
                                  onChanged: (s) {
                                    widget.cart.setPaymentSpecies(
                                      id:   s.id,
                                      name: s.name,
                                      days: s.days,
                                    );
                                    setState(() {});
                                  },
                                ),
                        ),
                        const SizedBox(height: 12),

                        // ── Condição de Pagamento (OBRIGATÓRIO) ────────────
                        _SectionCard(
                          title: 'Condição de Pagamento *',
                          child: _conditions.isEmpty
                              ? Text(
                                  'Nenhum parcelamento disponível. Sincronize o catálogo.',
                                  style: AppTypography.body.copyWith(color: AppColors.syncError),
                                )
                              : _PaymentConditionSelector(
                                  conditions: _conditions,
                                  selectedId: widget.cart.paymentConditionId,
                                  onChanged: (c) {
                                    widget.cart.setPaymentCondition(c);
                                    setState(() {});
                                  },
                                ),
                        ),
                        const SizedBox(height: 12),

                        // ── Natureza de Operação (OPCIONAL) ───────────────
                        if (_naturezas.isNotEmpty) ...[
                          _SectionCard(
                            title: 'Natureza de Operação',
                            child: _NaturezaSelector(
                              naturezas: _naturezas,
                              selectedId: widget.cart.naturezaId,
                              onChanged: (n) {
                                widget.cart.setNatureza(
                                  id:       n?.id,
                                  descricao: n?.descricao,
                                );
                                setState(() {});
                              },
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],

                        // Itens
                        _SectionCard(
                          title: '${items.length} ${items.length == 1 ? 'item' : 'itens'}',
                          child: Column(
                            children: items.map((item) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
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
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '${item.quantity.toStringAsFixed(item.quantity % 1 == 0 ? 0 : 2)} × ${_currencyFmt.format(item.product.price)}'
                                        '${item.discount > 0 ? '  -${item.discount.toStringAsFixed(0)}%' : ''}',
                                        style: AppTypography.quantity.copyWith(color: AppColors.textSecondary),
                                      ),
                                      Text(_currencyFmt.format(item.totalPrice), style: AppTypography.priceNormal),
                                    ],
                                  ),
                                ],
                              ),
                            )).toList(),
                          ),
                        ),

                        // ── Painel de desconto: bruto → desconto → líquido ──────
                        const SizedBox(height: 8),
                        _buildDiscountSummary(),

                        // Observações
                        if (notes != null && notes.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          _SectionCard(
                            title: 'Observações',
                            child: Text(notes, style: AppTypography.body.copyWith(color: AppColors.textSecondary)),
                          ),
                        ],

                        // Aviso offline-first
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.syncInProgressLight,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.syncInProgress),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline_rounded, color: AppColors.syncInProgress, size: 18),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'O pedido será salvo localmente e enviado ao ERP quando houver conexão.',
                                  style: AppTypography.badge.copyWith(color: AppColors.syncInProgress),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
          ),

          // ── Rodapé fixo: total + slide-to-confirm ───────────────────────
          Container(
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
                        Text('Total', style: AppTypography.fieldLabel.copyWith(color: AppColors.textSecondary)),
                        Text(_currencyFmt.format(total), style: AppTypography.priceLarge),
                      ],
                    ),
                    if (widget.cart.paymentSpeciesId == null || widget.cart.paymentConditionId == null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          '* Configure as opções de pagamento',
                          style: AppTypography.badge.copyWith(color: AppColors.syncError),
                        ),
                      ),
                    const SizedBox(height: 12),

                    // Slide-to-confirm (confirmação deliberada)
                    _SlideToConfirm(
                      label:       'Deslize para confirmar pedido',
                      onConfirmed: _onConfirm,
                      isLoading:   _confirming,
                      enabled:     widget.cart.paymentSpeciesId != null && widget.cart.paymentConditionId != null,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _PaymentSpeciesSelector
// ─────────────────────────────────────────────────────────────────────────────

/// Dropdown de espécie de pagamento (carregado do SQLite local).
class _PaymentSpeciesSelector extends StatelessWidget {
  final List<PaymentSpecies>    species;
  final String?                  selectedId;
  final ValueChanged<PaymentSpecies> onChanged;

  const _PaymentSpeciesSelector({
    required this.species,
    required this.selectedId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // Deduplica por ID para evitar crash do DropdownButton
    final uniqueSpecies = <String, PaymentSpecies>{};
    for (final s in species) {
      uniqueSpecies.putIfAbsent(s.id, () => s);
    }
    final items = uniqueSpecies.values.toList();

    // Garante que selected esteja na lista; se não, usa null (hint aparece)
    final selected = selectedId != null
        ? items.where((s) => s.id == selectedId).firstOrNull
        : null;

    return DropdownButtonHideUnderline(
      child: DropdownButton<PaymentSpecies>(
        isExpanded: true,
        value: selected,
        hint: Text('Selecione a forma de pagamento', style: AppTypography.body.copyWith(color: AppColors.textSecondary)),
        icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textSecondary),
        onChanged: (s) { if (s != null) onChanged(s); },
        items: items.map((s) => DropdownMenuItem(
          value: s,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(s.name, style: AppTypography.bodyBold),
              if (s.days != null && s.days! > 0)
                Text(
                  '${s.days} dias',
                  style: AppTypography.badge.copyWith(color: AppColors.textSecondary),
                ),
            ],
          ),
        )).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _PaymentConditionSelector
// ─────────────────────────────────────────────────────────────────────────────

/// Dropdown de condição de pagamento (carregado do SQLite local).
class _PaymentConditionSelector extends StatelessWidget {
  final List<PaymentCondition>    conditions;
  final String?                   selectedId;
  final ValueChanged<PaymentCondition> onChanged;

  const _PaymentConditionSelector({
    required this.conditions,
    required this.selectedId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // Deduplica por ID para evitar crash do DropdownButton
    final uniqueConditions = <String, PaymentCondition>{};
    for (final c in conditions) {
      uniqueConditions.putIfAbsent(c.id, () => c);
    }
    final items = uniqueConditions.values.toList();

    // Garante que selected esteja na lista; se não, usa null (hint aparece)
    final selected = selectedId != null
        ? items.where((c) => c.id == selectedId).firstOrNull
        : null;

    return DropdownButtonHideUnderline(
      child: DropdownButton<PaymentCondition>(
        isExpanded: true,
        value: selected,
        hint: Text('Selecione o parcelamento', style: AppTypography.body.copyWith(color: AppColors.textSecondary)),
        icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textSecondary),
        onChanged: (c) { if (c != null) onChanged(c); },
        items: items.map((c) => DropdownMenuItem(
          value: c,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(c.descricao, style: AppTypography.bodyBold),
              if (c.parcelas != null && c.parcelas! > 1)
                Text(
                  '${c.parcelas}x',
                  style: AppTypography.badge.copyWith(color: AppColors.textSecondary),
                ),
            ],
          ),
        )).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _NaturezaSelector
// ─────────────────────────────────────────────────────────────────────────────

/// Dropdown de natureza de operação, com opção de "Sem natureza".
class _NaturezaSelector extends StatelessWidget {
  final List<NaturezaOperacao>    naturezas;
  final String?                    selectedId;
  final ValueChanged<NaturezaOperacao?> onChanged;

  const _NaturezaSelector({
    required this.naturezas,
    required this.selectedId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selected = selectedId != null
        ? naturezas.where((n) => n.id == selectedId).firstOrNull
        : null;

    return DropdownButtonHideUnderline(
      child: DropdownButton<NaturezaOperacao?>(
        isExpanded: true,
        value: selected,
        hint: Text('Selecionar (opcional)', style: AppTypography.body.copyWith(color: AppColors.textSecondary)),
        icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textSecondary),
        onChanged: onChanged,
        items: [
          // Opção "sem natureza"
          DropdownMenuItem<NaturezaOperacao?>(
            value: null,
            child: Text('— Sem natureza de operação —', style: AppTypography.body.copyWith(color: AppColors.textSecondary)),
          ),
          ...naturezas.map((n) => DropdownMenuItem<NaturezaOperacao?>(
            value: n,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(n.descricao, style: AppTypography.bodyBold),
                if (n.codigoFiscal != null && n.codigoFiscal!.isNotEmpty)
                  Text(
                    'CFOP: ${n.codigoFiscal}',
                    style: AppTypography.badge.copyWith(color: AppColors.textSecondary),
                  ),
              ],
            ),
          )),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SectionCard
// ─────────────────────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfacePrimary,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTypography.badge.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SlideToConfirm — Botão de confirmação deliberada
// ─────────────────────────────────────────────────────────────────────────────

class _SlideToConfirm extends StatefulWidget {
  final String  label;
  final VoidCallback onConfirmed;
  final bool    isLoading;
  final bool    enabled;

  const _SlideToConfirm({
    required this.label,
    required this.onConfirmed,
    required this.isLoading,
    this.enabled = true,
  });

  @override
  State<_SlideToConfirm> createState() => _SlideToConfirmState();
}

class _SlideToConfirmState extends State<_SlideToConfirm>
    with SingleTickerProviderStateMixin {
  late AnimationController _holdController;
  bool _holding = false;

  @override
  void initState() {
    super.initState();
    _holdController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        HapticFeedback.heavyImpact();
        widget.onConfirmed();
      }
    });
  }

  @override
  void dispose() {
    _holdController.dispose();
    super.dispose();
  }

  void _onDown() {
    if (!widget.enabled || widget.isLoading) return;
    setState(() => _holding = true);
    HapticFeedback.lightImpact();
    _holdController.forward(from: 0);
  }

  void _onUp() {
    if (_holdController.isAnimating) {
      _holdController.reset();
    }
    setState(() => _holding = false);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isLoading) {
      return const SizedBox(
        height: 56,
        child: Center(child: CircularProgressIndicator(color: AppColors.actionPrimary)),
      );
    }

    final activeColor   = widget.enabled ? AppColors.syncSuccess     : AppColors.textSecondary;
    final activeBgColor = widget.enabled ? AppColors.syncSuccessLight : AppColors.surfaceSecondary;

    return GestureDetector(
      onTapDown:   (_) => _onDown(),
      onTapUp:     (_) => _onUp(),
      onTapCancel: _onUp,
      child: AnimatedBuilder(
        animation: _holdController,
        builder: (ctx, _) {
          final progress = _holdController.value;
          return Container(
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: activeColor, width: 1.5),
              color: activeBgColor,
            ),
            child: Stack(
              children: [
                // Progress fill
                FractionallySizedBox(
                  widthFactor: progress,
                  child: Container(
                    decoration: BoxDecoration(
                      color: activeColor.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                ),
                // Label
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _holding ? Icons.check_circle_rounded : Icons.touch_app_rounded,
                        color: activeColor,
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        widget.enabled
                          ? (_holding ? 'Segure para confirmar…' : 'Segure para confirmar pedido')
                          : 'Selecione a forma de pagamento',
                        style: AppTypography.badge.copyWith(
                          color: activeColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// CustomersScreen — Aba de Clientes: consulta e cadastro.
///
/// Funcionalidades:
/// - Lista de clientes com busca por nome/CNPJ (debounce 300ms)
/// - Detalhe compacto: nome, localização, CNPJ, saldo em aberto
/// - Botão FAB para cadastrar novo cliente localmente
library;

import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';
import '../../core/repositories/models/customer.dart';
import '../../core/repositories/customer_repository.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_typography.dart';
import '../../core/design/app_spacing.dart';
import '../../core/network/auto_sync_service.dart';
import '../../core/services/customer_service.dart';
import '../../core/repositories/financial_repository.dart';
import '../../core/sync/sync_service.dart';
import '../../core/session/session_service.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  final _repo        = GetIt.I<CustomerRepository>();
  final _finRepo     = GetIt.I<FinancialRepository>();
  final _autoSync    = GetIt.I<AutoSyncService>();
  final _searchCtrl  = TextEditingController();
  final _currencyFmt = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  List<Customer> _customers  = [];
  bool   _loading     = true;
  String _searchQuery = '';
  int    _totalCount  = 0;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _initLoad();
    // Refresh quando o sync termina (estado muda para success/partial)
    _autoSync.stateNotifier.addListener(_onSyncStateChanged);
  }

  @override
  void dispose() {
    _autoSync.stateNotifier.removeListener(_onSyncStateChanged);
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSyncStateChanged() {
    final state = _autoSync.stateNotifier.value;
    if (state == AutoSyncState.success || state == AutoSyncState.partial) {
      _initLoad();
    }
  }

  Future<void> _initLoad() async {
    _totalCount = await _repo.count();
    await _loadCustomers('');
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (query != _searchQuery) {
        _searchQuery = query;
        _loadCustomers(query);
      }
    });
  }

  Future<void> _loadCustomers(String query) async {
    if (!mounted) return;
    setState(() => _loading = true);
    final results = await _repo.search(query, limit: 200);
    if (!mounted) return;
    setState(() {
      _customers = results;
      _loading   = false;
    });
  }

  void _openNew() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _NewCustomerSheet(
        repo: _repo,
        onSaved: () {
          _totalCount++;
          _loadCustomers(_searchQuery);
        },
      ),
    );
  }

  void _openDetail(Customer c) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _CustomerDetailSheet(customer: c, currency: _currencyFmt),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.surfaceDM : AppColors.surfaceSecondary,
      body: CustomScrollView(
        slivers: [
          // ── App Bar ───────────────────────────────────────────────────────
          SliverAppBar(
            pinned: true,
            title: const Text('Clientes'),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(56),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: SearchBar(
                  controller: _searchCtrl,
                  hintText: 'Buscar por nome ou CNPJ...',
                  leading: const Icon(Icons.search, size: 20),
                  trailing: [
                    if (_searchQuery.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          _onSearchChanged('');
                        },
                      ),
                  ],
                  onChanged: _onSearchChanged,
                  padding: const WidgetStatePropertyAll(
                    EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
              ),
            ),
          ),

          // ── Count header ──────────────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            sliver: SliverToBoxAdapter(
              child: Text(
                _searchQuery.isEmpty
                    ? '$_totalCount clientes'
                    : '${_customers.length} resultados',
                style: AppTypography.caption
                    .copyWith(color: AppColors.textSecondary),
              ),
            ),
          ),

          // ── List ──────────────────────────────────────────────────────────
          if (_loading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_customers.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.people_outline, size: 48,
                        color: AppColors.textTertiary),
                    const SizedBox(height: 12),
                    Text('Nenhum cliente encontrado',
                        style: AppTypography.body
                            .copyWith(color: AppColors.textSecondary)),
                  ],
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) => _CustomerTile(
                  customer: _customers[i],
                  currency: _currencyFmt,
                  finRepo:  _finRepo,
                  onTap: () => _openDetail(_customers[i]),
                ),
                childCount: _customers.length,
              ),
            ),
        ],
      ),

      // ── FAB — Novo cliente ────────────────────────────────────────────────
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openNew,
        icon: const Icon(Icons.person_add_rounded),
        label: const Text('Novo Cliente'),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _CustomerTile
// ─────────────────────────────────────────────────────────────────────────────

class _CustomerTile extends StatelessWidget {
  final Customer            customer;
  final NumberFormat        currency;
  final FinancialRepository finRepo;
  final VoidCallback        onTap;

  const _CustomerTile({
    required this.customer,
    required this.currency,
    required this.finRepo,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDM : AppColors.surfacePrimary,
          border: const Border(
            bottom: BorderSide(color: AppColors.divider, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(isDark ? 0.2 : 0.1),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Center(
                child: Text(
                  customer.name.isNotEmpty
                      ? customer.name[0].toUpperCase()
                      : '?',
                  style: AppTypography.bodyBold.copyWith(
                      color: AppColors.primary),
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    customer.name,
                    style: AppTypography.body.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? AppColors.textPrimaryDM
                          : AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (customer.location.isNotEmpty) customer.location,
                      if (customer.cnpj != null && customer.cnpj!.isNotEmpty)
                        customer.cnpj!,
                    ].join(' · '),
                    style: AppTypography.caption
                        .copyWith(color: AppColors.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // Saldo em aberto
            FutureBuilder<double>(
              future: finRepo.totalOpenByCustomer(customer.id),
              builder: (ctx, snap) {
                if (!snap.hasData || snap.data! <= 0) {
                  return const SizedBox.shrink();
                }
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE3F2FD),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFF90CAF9)),
                  ),
                  child: Text(
                    currency.format(snap.data!),
                    style: AppTypography.caption.copyWith(
                      color: const Color(0xFF1565C0),
                      fontWeight: FontWeight.w600,
                      fontSize: 10,
                    ),
                  ),
                );
              },
            ),

            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 16,
                color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _EditContactSheet — Edição restrita: APENAS telefone e e-mail
// Clientes ERP não podem ter dados cadastrais completos alterados (segurança).
// ─────────────────────────────────────────────────────────────────────────────

class _EditContactSheet extends StatefulWidget {
  final Customer customer;
  const _EditContactSheet({required this.customer});

  @override
  State<_EditContactSheet> createState() => _EditContactSheetState();
}

class _EditContactSheetState extends State<_EditContactSheet> {
  final _formKey    = GlobalKey<FormState>();
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _emailCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _phoneCtrl = TextEditingController(text: widget.customer.phone ?? '');
    _emailCtrl = TextEditingController(text: widget.customer.email ?? '');
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final dio = GetIt.I<Dio>();
      await dio.patch(
        '/api/sync/update-customer/${widget.customer.id}',
        data: {
          'phone': _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
          'email': _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
        },
      );

      // Atualiza SQLite local para refletir imediatamente
      final repo    = GetIt.I<CustomerRepository>();
      final updated = widget.customer.copyWith(
        phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        email: _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
      );
      await repo.upsertBatch([updated]);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Contato atualizado com sucesso'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop(updated);
    } on DioException catch (e) {
      if (!mounted) return;
      final msg = (e.response?.data as Map?)?['error'] ?? 'Erro ao atualizar contato';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg.toString()),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.border, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Row(children: [
              const Icon(Icons.edit_outlined, color: AppColors.primary, size: 18),
              const SizedBox(width: 8),
              Text('Editar Contato', style: AppTypography.headingMedium),
            ]),
            const SizedBox(height: 4),
            Text(widget.customer.name,
                style: AppTypography.caption
                    .copyWith(color: AppColors.textSecondary)),
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.10),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.warning.withOpacity(0.4)),
              ),
              child: Row(children: [
                const Icon(Icons.lock_outline, size: 14, color: AppColors.warning),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Por segurança, somente telefone e e-mail podem ser alterados pelo app.',
                    style: AppTypography.caption
                        .copyWith(color: AppColors.warning, fontSize: 11),
                  ),
                ),
              ]),
            ),
            TextFormField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              inputFormatters: [PhoneMaskFormatter()],
              decoration: const InputDecoration(
                labelText: 'Celular',
                prefixIcon: Icon(Icons.phone_android_outlined),
                hintText: '(99) 99999-9999',
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              maxLength: 50,
              buildCounter: (_, {required currentLength,
                  required isFocused, required maxLength}) => null,
              decoration: const InputDecoration(
                labelText: 'E-mail',
                prefixIcon: Icon(Icons.email_outlined),
                hintText: 'email@empresa.com.br',
              ),
              validator: (v) {
                if (v != null && v.isNotEmpty && !v.contains('@')) {
                  return 'E-mail inválido';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Salvar Contato'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
class _CustomerDetailSheet extends StatefulWidget {
  final Customer     customer;
  final NumberFormat currency;

  const _CustomerDetailSheet({
    required this.customer,
    required this.currency,
  });

  @override
  State<_CustomerDetailSheet> createState() => _CustomerDetailSheetState();
}

class _CustomerDetailSheetState extends State<_CustomerDetailSheet> {
  late Customer _customer;
  final _customerService = GetIt.I<CustomerService>();
  final _finRepo         = GetIt.I<FinancialRepository>();
  final _sync            = GetIt.I<SyncService>();

  CustomerInsight? _insight;
  List<Financial> _openTitles = [];
  List<Map<String, dynamic>> _topProducts = [];
  List<Map<String, dynamic>> _orderHistory = [];
  bool _loadingInsight = true;

  @override
  void initState() {
    super.initState();
    _customer = widget.customer;
    _loadInsight();
  }

  Future<void> _loadInsight() async {
    // Pull financials do servidor em background (atualiza SQLite)
    try {
      await _sync.pullFinancialsForCustomer(_customer.id);
    } catch (_) {
      // silencioso — exibe dados locais se pull falhar
    }

    try {
      final results = await Future.wait([
        _customerService.getInsight(_customer.id),
        _customerService.topProducts(_customer.id, limit: 5),
        _customerService.orderHistory(_customer.id, limit: 5),
        _finRepo.getByCustomer(_customer.id),
      ]);
      if (mounted) {
        setState(() {
          _insight = results[0] as CustomerInsight;
          _topProducts = results[1] as List<Map<String, dynamic>>;
          _orderHistory = results[2] as List<Map<String, dynamic>>;
          _openTitles = results[3] as List<Financial>;
          _loadingInsight = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingInsight = false);
    }
  }

  Widget _row(String label, String value,
      {VoidCallback? onTap, Color? valueColor}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 95,
              child: Text(label,
                  style: AppTypography.caption
                      .copyWith(color: AppColors.textSecondary)),
            ),
            Expanded(
              child: GestureDetector(
                onTap: onTap,
                child: Text(
                  value,
                  style: AppTypography.body.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: onTap != null
                        ? AppColors.primary
                        : valueColor,
                    decoration: onTap != null
                        ? TextDecoration.underline
                        : null,
                  ),
                ),
              ),
            ),
          ],
        ),
      );

  Future<void> _openEditContact() async {
    final updated = await showModalBottomSheet<Customer>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditContactSheet(customer: _customer),
    );
    if (updated != null && mounted) {
      setState(() => _customer = updated);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDM : AppColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            // Handle
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header
            Row(
              children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      _customer.name.isNotEmpty ? _customer.name[0].toUpperCase() : '?',
                      style: AppTypography.headingLarge.copyWith(color: AppColors.primary, fontSize: 20),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_customer.name,
                          style: AppTypography.headingMedium,
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      if (_customer.cnpj != null && _customer.cnpj!.isNotEmpty)
                        Text(_customer.cnpj!,
                            style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // ── KPI Row ─────────────────────────────────────────
            if (_loadingInsight)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (_insight != null)
              _buildKpiSection(),

            const Divider(height: 16),

            // ── Identificação ─────────────────────────────────
            _sectionTitle(Icons.badge_outlined, 'Identificação'),
            if (_customer.cnpj != null && _customer.cnpj!.isNotEmpty)
              _row('CNPJ/CPF', _customer.cnpj!),
            _row('ID ERP', _customer.id),

            if (_insight != null && _insight!.openBalance > 0)
              _row('Saldo Aberto', widget.currency.format(_insight!.openBalance),
                valueColor: const Color(0xFF1565C0)),

            const Divider(height: 16),

            // ── Endereço ──────────────────────────────────────
            _sectionTitle(Icons.location_on_outlined, 'Endereço'),
            if (_customer.street != null && _customer.street!.isNotEmpty)
              _row('Logradouro', _customer.street!),
            if (_customer.streetNumber != null && _customer.streetNumber!.isNotEmpty)
              _row('Número', _customer.streetNumber!),
            if (_customer.neighborhood != null && _customer.neighborhood!.isNotEmpty)
              _row('Bairro', _customer.neighborhood!),
            if (_customer.zipCode != null && _customer.zipCode!.isNotEmpty)
              _row('CEP', _customer.zipCode!),
            if (_customer.city != null && _customer.city!.isNotEmpty)
              _row('Cidade', '${_customer.city!}${_customer.state != null ? ' - ${_customer.state}' : ''}'),

            const Divider(height: 16),

            // ── Contato (com botão de editar) ─────────────────
            Row(
              children: [
                const Icon(Icons.contact_phone_outlined, size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Text('Contato', style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary, fontWeight: FontWeight.w700)),
                const Spacer(),
                if (!_customer.id.startsWith('local_'))
                  TextButton.icon(
                    onPressed: _openEditContact,
                    icon: const Icon(Icons.edit_outlined, size: 14),
                    label: const Text('Editar'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            if (_customer.phone != null && _customer.phone!.isNotEmpty)
              _row('Telefone', _customer.phone!),
            if (_customer.email != null && _customer.email!.isNotEmpty)
              _row('E-mail', _customer.email!),

            // ── Títulos em Aberto ──────────────────────────────
            if (!_loadingInsight) ...[
              const Divider(height: 16),
              _sectionTitle(Icons.description_outlined, 'Títulos em Aberto'),
              const SizedBox(height: 8),
              if (_openTitles.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle_outline, size: 16, color: AppColors.success),
                      const SizedBox(width: 8),
                      Text('Nenhum título em aberto',
                        style: AppTypography.caption.copyWith(color: AppColors.success)),
                    ],
                  ),
                )
              else ...[
                ..._openTitles.map((t) => _buildTitleRow(t, isDark)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1565C0).withOpacity(0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF1565C0).withOpacity(0.2)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Total em Aberto',
                        style: AppTypography.bodyBold.copyWith(fontSize: 12, color: const Color(0xFF1565C0))),
                      Text(widget.currency.format(
                          _openTitles.fold<double>(0, (s, t) => s + t.total)),
                        style: AppTypography.bodyBold.copyWith(fontSize: 13, color: const Color(0xFF1565C0))),
                    ],
                  ),
                ),
              ],
            ],

            // ── Top Produtos ──────────────────────────────────
            if (_topProducts.isNotEmpty) ...[
              const Divider(height: 16),
              _sectionTitle(Icons.star_outline_rounded, 'Produtos Mais Comprados'),
              const SizedBox(height: 8),
              ..._topProducts.map((p) => _buildTopProductRow(p, isDark)),
            ],

            // ── Histórico de Pedidos ──────────────────────────
            if (_orderHistory.isNotEmpty) ...[
              const Divider(height: 16),
              _sectionTitle(Icons.receipt_long_outlined, 'Últimos Pedidos'),
              const SizedBox(height: 8),
              ..._orderHistory.map((o) => _buildOrderHistoryRow(o, isDark)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(IconData icon, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        Icon(icon, size: 14, color: AppColors.textSecondary),
        const SizedBox(width: 6),
        Text(title, style: AppTypography.caption.copyWith(
          color: AppColors.textSecondary, fontWeight: FontWeight.w700)),
      ]),
    );
  }

  Widget _buildKpiSection() {
    final insight = _insight!;
    return Column(
      children: [
        // KPI cards row
        Row(
          children: [
            Expanded(child: _kpiMini(
              icon: Icons.attach_money_rounded,
              label: 'Total Comprado',
              value: widget.currency.format(insight.totalPurchased),
              color: AppColors.success,
            )),
            const SizedBox(width: 8),
            Expanded(child: _kpiMini(
              icon: Icons.receipt_long_outlined,
              label: 'Pedidos',
              value: '${insight.totalOrders}',
              color: AppColors.primary,
            )),
            const SizedBox(width: 8),
            Expanded(child: _kpiMini(
              icon: Icons.trending_up_rounded,
              label: 'Ticket Médio',
              value: widget.currency.format(insight.averageTicket),
              color: AppColors.info,
            )),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            // Days since last order
            Expanded(
              child: _kpiMini(
                icon: Icons.calendar_today_outlined,
                label: 'Último Pedido',
                value: insight.lastOrderDate != null
                    ? '${insight.daysSinceLastOrder}d atrás'
                    : 'Nunca',
                color: insight.daysSinceLastOrder > 30
                    ? AppColors.warning
                    : AppColors.success,
              ),
            ),
            const SizedBox(width: 8),
            // Open balance
            Expanded(
              child: _kpiMini(
                icon: Icons.account_balance_wallet_outlined,
                label: 'Saldo Aberto',
                value: insight.openBalance > 0
                    ? widget.currency.format(insight.openBalance)
                    : 'Nenhum',
                color: insight.openBalance > 0 ? const Color(0xFF1976D2) : AppColors.success,
              ),
            ),
            const SizedBox(width: 8),
            const Expanded(child: SizedBox()),
          ],
        ),
      ],
    );
  }

  Widget _kpiMini({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 4),
          Text(value, style: AppTypography.bodyBold.copyWith(fontSize: 12, color: color),
            maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(label, style: AppTypography.badge.copyWith(fontSize: 9, color: color.withOpacity(0.7)),
            maxLines: 1),
        ],
      ),
    );
  }

  Widget _buildTopProductRow(Map<String, dynamic> p, bool isDark) {
    final name = p['product_name'] as String? ?? '';
    final code = p['product_code'] as String? ?? '';
    final totalQty = (p['total_qty'] as num?)?.toDouble() ?? 0;
    final timesOrdered = (p['times_ordered'] as num?)?.toInt() ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceElevatedDM : AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isDark ? AppColors.borderDark : AppColors.border, width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            padding: const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(child: Text(code, style: AppTypography.badge.copyWith(
              fontSize: 9, color: AppColors.primary, fontWeight: FontWeight.w700),
              maxLines: 1, overflow: TextOverflow.ellipsis)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(name, style: AppTypography.body.copyWith(fontSize: 12, fontWeight: FontWeight.w500),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          Text('${totalQty.toStringAsFixed(0)}x · $timesOrdered ped',
            style: AppTypography.badge.copyWith(color: AppColors.textSecondary, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _buildOrderHistoryRow(Map<String, dynamic> o, bool isDark) {
    final total = (o['total_amount'] as num?)?.toDouble() ?? 0;
    final createdAt = o['created_at'] as String?;
    final syncStatus = o['sync_status'] as String? ?? 'pending';
    final date = createdAt != null ? DateTime.tryParse(createdAt) : null;
    final dateStr = date != null ? DateFormat('dd/MM/yy').format(date) : '—';

    final (color, icon) = switch (syncStatus) {
      'synced'  => (AppColors.success, Icons.check_circle_outline),
      'error'   => (AppColors.error, Icons.error_outline),
      _         => (AppColors.warning, Icons.schedule_rounded),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceElevatedDM : AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isDark ? AppColors.borderDark : AppColors.border, width: 0.5),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(dateStr, style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600)),
          const Spacer(),
          Text(widget.currency.format(total),
            style: AppTypography.bodyBold.copyWith(fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildTitleRow(Financial t, bool isDark) {
    final dueDateParsed = t.dueDate != null ? DateTime.tryParse(t.dueDate!) : null;
    final dueDateStr = dueDateParsed != null
        ? DateFormat('dd/MM/yy').format(dueDateParsed)
        : '—';

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceElevatedDM : AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: t.isOverdue
              ? Colors.red.shade200
              : (isDark ? AppColors.borderDark : AppColors.border),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          // Ícone de status
          Icon(
            t.isOverdue ? Icons.warning_amber_rounded : Icons.description_outlined,
            size: 16,
            color: t.isOverdue ? AppColors.error : const Color(0xFF1976D2),
          ),
          const SizedBox(width: 8),
          // Doc linear and aligned using Expanded + flex
          Expanded(
            flex: 10,
            child: Text(
              t.docNumber != null && t.docNumber!.isNotEmpty ? 'Doc: ${t.docNumber}' : 'Doc: —',
              style: AppTypography.caption.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 11,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          // Vencimento
          Expanded(
            flex: 11,
            child: Text(
              'Venc: $dueDateStr',
              style: AppTypography.badge.copyWith(
                color: t.isOverdue ? AppColors.error : AppColors.textSecondary,
                fontSize: 10,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Badge vencido (only when overdue)
          if (t.isOverdue) ...[
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Text(
                'Vencido',
                style: AppTypography.badge.copyWith(
                  color: Colors.red.shade700,
                  fontSize: 8,
                ),
              ),
            ),
          ],
          const SizedBox(width: 8),
          // Valor
          Expanded(
            flex: 9,
            child: Text(
              widget.currency.format(t.total),
              textAlign: TextAlign.right,
              style: AppTypography.bodyBold.copyWith(
                fontSize: 12,
                color: t.isOverdue ? AppColors.error : const Color(0xFF1565C0),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
// ─────────────────────────────────────────────────────────────────────────────
// _NewCustomerSheet — Formulário de cadastro rápido
// ─────────────────────────────────────────────────────────────────────────────

class _NewCustomerSheet extends StatefulWidget {
  final CustomerRepository repo;
  final VoidCallback        onSaved;

  const _NewCustomerSheet({required this.repo, required this.onSaved});

  @override
  State<_NewCustomerSheet> createState() => _NewCustomerSheetState();
}

class _NewCustomerSheetState extends State<_NewCustomerSheet> {
  final _formKey        = GlobalKey<FormState>();
  final _nameCtrl       = TextEditingController();
  final _cnpjCtrl       = TextEditingController();
  final _phoneCtrl      = TextEditingController();
  final _emailCtrl      = TextEditingController();
  final _streetCtrl     = TextEditingController();
  final _numberCtrl     = TextEditingController();
  final _neighborCtrl   = TextEditingController();
  final _zipCtrl        = TextEditingController();
  final _cityCtrl       = TextEditingController();
  final _stateCtrl      = TextEditingController();

  bool _saving = false;
  String _lastCheckedCep = '';
  bool _fetchingCep = false;
  String _lastCheckedCnpj = '';
  bool _fetchingCnpj = false;
  String? _duplicateError;

  @override
  void initState() {
    super.initState();
    _zipCtrl.addListener(_onCepChanged);
    _cnpjCtrl.addListener(_onCnpjChanged);
  }

  @override
  void dispose() {
    _zipCtrl.removeListener(_onCepChanged);
    _cnpjCtrl.removeListener(_onCnpjChanged);
    _nameCtrl.dispose();
    _cnpjCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _streetCtrl.dispose();
    _numberCtrl.dispose();
    _neighborCtrl.dispose();
    _zipCtrl.dispose();
    _cityCtrl.dispose();
    _stateCtrl.dispose();
    super.dispose();
  }

  void _onCepChanged() {
    final cep = _zipCtrl.text.replaceAll(RegExp(r'\D'), '');
    if (cep.length == 8 && cep != _lastCheckedCep) {
      _lastCheckedCep = cep;
      _lookupCep(cep);
    }
  }

  void _onCnpjChanged() async {
    final cnpj = _cnpjCtrl.text.replaceAll(RegExp(r'\D'), '');
    if ((cnpj.length == 14 || cnpj.length == 11) && cnpj != _lastCheckedCnpj) {
      _lastCheckedCnpj = cnpj;
      
      setState(() => _duplicateError = null);
      
      final existing = await widget.repo.getByCnpjOrCpf(cnpj);
      if (existing != null) {
        setState(() {
          _duplicateError = 'Já cadastrado: ${existing.name}';
        });
        return;
      }
      
      if (cnpj.length == 14) {
        _lookupCnpj(cnpj);
      }
    } else if (cnpj.length != 14 && cnpj.length != 11 && _duplicateError != null) {
      setState(() => _duplicateError = null);
    }
  }

  String _formatCepStr(String cep) {
    final digits = cep.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 8) {
      return '${digits.substring(0, 5)}-${digits.substring(5)}';
    }
    return cep;
  }

  String _formatPhoneStr(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 11) {
      return '(${digits.substring(0, 2)}) ${digits.substring(2, 7)}-${digits.substring(7)}';
    }
    if (digits.length == 10) {
      return '(${digits.substring(0, 2)}) ${digits.substring(2, 6)}-${digits.substring(6)}';
    }
    return phone;
  }

  Future<void> _lookupCep(String cep) async {
    if (_fetchingCep) return;
    setState(() => _fetchingCep = true);

    try {
      final dio = GetIt.I<Dio>();
      final response = await dio.get('https://viacep.com.br/ws/$cep/json/');
      if (response.statusCode == 200 && response.data is Map) {
        final data = response.data as Map;
        if (data['erro'] == true) {
          return;
        }

        setState(() {
          if (data['logradouro'] != null && data['logradouro'].toString().isNotEmpty) {
            _streetCtrl.text = data['logradouro'].toString();
          }
          if (data['bairro'] != null && data['bairro'].toString().isNotEmpty) {
            _neighborCtrl.text = data['bairro'].toString();
          }
          if (data['localidade'] != null && data['localidade'].toString().isNotEmpty) {
            _cityCtrl.text = data['localidade'].toString();
          }
          if (data['uf'] != null && data['uf'].toString().isNotEmpty) {
            _stateCtrl.text = data['uf'].toString().toUpperCase();
          }
        });
      }
    } catch (e) {
      debugPrint('Erro ao buscar CEP: $e');
    } finally {
      if (mounted) {
        setState(() => _fetchingCep = false);
      }
    }
  }

  Future<void> _lookupCnpj(String cnpj) async {
    if (_fetchingCnpj) return;
    setState(() => _fetchingCnpj = true);

    try {
      final dio = GetIt.I<Dio>();
      final response = await dio.get('https://brasilapi.com.br/api/cnpj/v1/$cnpj');
      if (response.statusCode == 200 && response.data is Map) {
        final data = response.data as Map;

        setState(() {
          if (data['razao_social'] != null && data['razao_social'].toString().isNotEmpty) {
            _nameCtrl.text = data['razao_social'].toString();
          } else if (data['nome_fantasia'] != null && data['nome_fantasia'].toString().isNotEmpty) {
            _nameCtrl.text = data['nome_fantasia'].toString();
          }

          if (data['ddd_telefone_1'] != null && data['ddd_telefone_1'].toString().isNotEmpty) {
            _phoneCtrl.text = _formatPhoneStr(data['ddd_telefone_1'].toString());
          }

          if (data['email'] != null && data['email'].toString().isNotEmpty) {
            _emailCtrl.text = data['email'].toString();
          }

          if (data['cep'] != null && data['cep'].toString().isNotEmpty) {
            _zipCtrl.text = _formatCepStr(data['cep'].toString());
          }

          if (data['logradouro'] != null && data['logradouro'].toString().isNotEmpty) {
            _streetCtrl.text = data['logradouro'].toString();
          }

          if (data['numero'] != null && data['numero'].toString().isNotEmpty) {
            _numberCtrl.text = data['numero'].toString();
          }

          if (data['bairro'] != null && data['bairro'].toString().isNotEmpty) {
            _neighborCtrl.text = data['bairro'].toString();
          }

          if (data['municipio'] != null && data['municipio'].toString().isNotEmpty) {
            _cityCtrl.text = data['municipio'].toString();
          }

          if (data['uf'] != null && data['uf'].toString().isNotEmpty) {
            _stateCtrl.text = data['uf'].toString().toUpperCase();
          }
        });
      }
    } catch (e) {
      debugPrint('Erro ao buscar CNPJ: $e');
    } finally {
      if (mounted) {
        setState(() => _fetchingCnpj = false);
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    String? n(String v) => v.trim().isEmpty ? null : v.trim();
    final session = GetIt.I<SessionService>();

    final customer = Customer(
      id:           'local_${DateTime.now().millisecondsSinceEpoch}',
      name:         _nameCtrl.text.trim(),
      cnpj:         n(_cnpjCtrl.text),
      phone:        n(_phoneCtrl.text),
      email:        n(_emailCtrl.text),
      street:       n(_streetCtrl.text),
      streetNumber: n(_numberCtrl.text),
      neighborhood: n(_neighborCtrl.text),
      zipCode:      n(_zipCtrl.text),
      city:         n(_cityCtrl.text),
      state:        n(_stateCtrl.text),
      creditLimit:  0,
      sellerId:     session.sellerId,
    );

    await widget.repo.upsertBatch([customer]);

    if (!mounted) return;
    widget.onSaved();
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${customer.name} cadastrado localmente'),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 20, 20, bottom + 20),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.person_add_rounded,
                    color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Text('Novo Cliente', style: AppTypography.headingMedium),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Nome *
            TextFormField(
              controller: _nameCtrl,
              maxLength: 50,
              buildCounter: (_, {required currentLength,
                  required isFocused, required maxLength}) => null,
              decoration: const InputDecoration(
                labelText: 'Nome / Razão Social *',
                hintText: 'Ex: Empresa ABC Ltda',
              ),
              textCapitalization: TextCapitalization.words,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Nome obrigatório' : null,
            ),
            const SizedBox(height: 10),

            // CNPJ / CPF
            TextFormField(
              controller: _cnpjCtrl,
              decoration: InputDecoration(
                labelText: 'CNPJ / CPF',
                hintText: 'Ex: 00.000.000/0000-00',
                errorText: _duplicateError,
                errorMaxLines: 3,
                suffixIcon: _fetchingCnpj
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: Padding(
                          padding: EdgeInsets.all(10.0),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : const Icon(Icons.corporate_fare_outlined, size: 18),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [CpfCnpjMaskFormatter()],
              validator: (v) {
                if (_duplicateError != null) {
                  return 'Cliente já cadastrado';
                }
                return null;
              },
            ),
            const SizedBox(height: 10),

            // Telefone + E-mail
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _phoneCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Telefone',
                      hintText: 'Ex: (67) 99999-9999',
                    ),
                    keyboardType: TextInputType.phone,
                    inputFormatters: [PhoneMaskFormatter()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _emailCtrl,
              maxLength: 50,
              buildCounter: (_, {required currentLength,
                  required isFocused, required maxLength}) => null,
              decoration: const InputDecoration(
                labelText: 'E-mail',
                hintText: 'email@empresa.com.br',
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 10),

            // Endereço
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: _zipCtrl,
                    decoration: InputDecoration(
                      labelText: 'CEP',
                      hintText: '79000-000',
                      suffixIcon: _fetchingCep
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: Padding(
                                padding: EdgeInsets.all(10.0),
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : const Icon(Icons.map_outlined, size: 18),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [CepMaskFormatter()],
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 80,
                  child: TextFormField(
                    controller: _numberCtrl,
                    maxLength: 10,
                    buildCounter: (_, {required currentLength,
                        required isFocused, required maxLength}) => null,
                    decoration: const InputDecoration(
                      labelText: 'Nº',
                    ),
                    keyboardType: TextInputType.text,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _streetCtrl,
              maxLength: 50,
              buildCounter: (_, {required currentLength,
                  required isFocused, required maxLength}) => null,
              decoration: const InputDecoration(
                labelText: 'Logradouro',
                hintText: 'Rua, Av...',
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: _neighborCtrl,
                    maxLength: 30,
                    buildCounter: (_, {required currentLength,
                        required isFocused, required maxLength}) => null,
                    decoration: const InputDecoration(
                      labelText: 'Bairro',
                    ),
                    textCapitalization: TextCapitalization.words,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: _cityCtrl,
                    maxLength: 50,
                    buildCounter: (_, {required currentLength,
                        required isFocused, required maxLength}) => null,
                    decoration: const InputDecoration(
                      labelText: 'Cidade',
                    ),
                    textCapitalization: TextCapitalization.words,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 1,
                  child: TextFormField(
                    controller: _stateCtrl,
                    decoration: const InputDecoration(
                      labelText: 'UF',
                      hintText: 'MS',
                    ),
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 2,
                    buildCounter: (_, {required currentLength,
                        required isFocused, required maxLength}) => null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Aviso
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.warning.withOpacity(0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      size: 16, color: AppColors.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Cadastro local — será sincronizado com o ERP na próxima sincronização completa.',
                      style: AppTypography.caption
                          .copyWith(color: AppColors.warning),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Salvar Cliente'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Formatadores de Máscara Customizados
// ─────────────────────────────────────────────────────────────────────────────

class CpfCnpjMaskFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;

    final digits = text.replaceAll(RegExp(r'\D'), '');
    final limitedDigits = digits.length > 14 ? digits.substring(0, 14) : digits;
    final limitedLength = limitedDigits.length;

    String formattedText = '';
    if (limitedLength <= 11) {
      for (int i = 0; i < limitedLength; i++) {
        if (i == 3 || i == 6) {
          formattedText += '.';
        } else if (i == 9) {
          formattedText += '-';
        }
        formattedText += limitedDigits[i];
      }
    } else {
      for (int i = 0; i < limitedLength; i++) {
        if (i == 2 || i == 5) {
          formattedText += '.';
        } else if (i == 8) {
          formattedText += '/';
        } else if (i == 12) {
          formattedText += '-';
        }
        formattedText += limitedDigits[i];
      }
    }

    return TextEditingValue(
      text: formattedText,
      selection: TextSelection.collapsed(offset: formattedText.length),
    );
  }
}

class PhoneMaskFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;

    final digits = text.replaceAll(RegExp(r'\D'), '');
    final limitedDigits = digits.length > 11 ? digits.substring(0, 11) : digits;
    final limitedLength = limitedDigits.length;

    String formattedText = '';
    if (limitedLength <= 10) {
      for (int i = 0; i < limitedLength; i++) {
        if (i == 0) {
          formattedText += '(';
        } else if (i == 2) {
          formattedText += ') ';
        } else if (i == 6) {
          formattedText += '-';
        }
        formattedText += limitedDigits[i];
      }
    } else {
      for (int i = 0; i < limitedLength; i++) {
        if (i == 0) {
          formattedText += '(';
        } else if (i == 2) {
          formattedText += ') ';
        } else if (i == 7) {
          formattedText += '-';
        }
        formattedText += limitedDigits[i];
      }
    }

    return TextEditingValue(
      text: formattedText,
      selection: TextSelection.collapsed(offset: formattedText.length),
    );
  }
}

class CepMaskFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;

    final digits = text.replaceAll(RegExp(r'\D'), '');
    final limitedDigits = digits.length > 8 ? digits.substring(0, 8) : digits;
    final limitedLength = limitedDigits.length;

    String formattedText = '';
    for (int i = 0; i < limitedLength; i++) {
      if (i == 5) {
        formattedText += '-';
      }
      formattedText += limitedDigits[i];
    }

    return TextEditingValue(
      text: formattedText,
      selection: TextSelection.collapsed(offset: formattedText.length),
    );
  }
}

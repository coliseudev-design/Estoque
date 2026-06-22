/// CustomerSearchScreen — Busca e seleção de cliente para o pedido.
///
/// UX FIELD RULES:
/// - Debounce 300ms (não dispara a cada tecla)
/// - Lista virtualizada para listas grandes
/// - Mostrar localização e CNPJ para identificação rápida em campo
/// - Badge de débito em aberto por cliente (dados locais do SQLite)
/// - Seleção fecha a tela e retorna o cliente ao chamador
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';
import '../../../core/repositories/models/customer.dart';
import '../../../core/repositories/customer_repository.dart';
import '../../../core/repositories/financial_repository.dart';
import '../../../core/sync/sync_service.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_typography.dart';

class CustomerSearchScreen extends StatefulWidget {
  const CustomerSearchScreen({super.key});

  /// Abre a tela e retorna o [Customer] selecionado ou null se cancelado.
  static Future<Customer?> show(BuildContext context) {
    return Navigator.push<Customer>(
      context,
      MaterialPageRoute(builder: (_) => const CustomerSearchScreen()),
    );
  }

  @override
  State<CustomerSearchScreen> createState() => _CustomerSearchScreenState();
}

class _CustomerSearchScreenState extends State<CustomerSearchScreen> {
  final CustomerRepository   _repo       = GetIt.I<CustomerRepository>();
  final SyncService          _sync       = GetIt.I<SyncService>();
  final FinancialRepository  _finRepo    = GetIt.I<FinancialRepository>();
  final TextEditingController _searchCtrl = TextEditingController();
  final _currencyFmt = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  List<Customer> _customers = [];
  bool    _loading      = true;
  String  _searchQuery  = '';
  Timer?  _debounce;
  int     _totalCount   = 0;

  @override
  void initState() {
    super.initState();
    _initLoad();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _initLoad() async {
    _totalCount = await _repo.count();
    if (!mounted) return;
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
    setState(() => _loading = true);
    final results = await _repo.search(query, limit: 150);
    if (!mounted) return;
    setState(() {
      _customers = results;
      _loading   = false;
    });
  }

  /// Seleciona o cliente e dispara pull de financeiros em background.
  ///
  /// O Navigator.pop() acontece imediatamente — a tela não bloqueia aguardando
  /// o pull. Os dados financeiros ficam disponíveis no SQLite assim que chegarem.
  void _onSelect(Customer customer) {
    // Pop imediato — UX não bloqueada
    Navigator.of(context).pop(customer);

    // Pull em background — atualiza financeiros para esse cliente
    _sync.pullFinancialsForCustomer(customer.id).then((count) {
      if (count > 0) {
        debugPrint('[CustomerSearch] $count títulos financeiros carregados para ${customer.id}');
      }
    }).catchError((_) {});
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceSecondary,
      appBar: AppBar(
        title: const Text('Selecionar Cliente'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: TextField(
              controller: _searchCtrl,
              autofocus: true,
              onChanged: _onSearchChanged,
              style: AppTypography.body,
              decoration: InputDecoration(
                hintText: 'Nome ou CNPJ...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // Contador de resultados
          if (!_loading)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: AppColors.surfaceSecondary,
              child: Text(
                _customers.isEmpty
                    ? 'Nenhum cliente encontrado'
                    : _searchQuery.isEmpty
                        ? '$_totalCount clientes cadastrados'
                        : '${_customers.length} resultado${_customers.length != 1 ? 's' : ''}',
                style: AppTypography.badge.copyWith(color: AppColors.textSecondary),
              ),
            ),

          // Lista
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _customers.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        itemCount: _customers.length,
                        itemExtent: 72,
                        itemBuilder: (_, i) => _CustomerTile(
                          customer:    _customers[i],
                          currencyFmt: _currencyFmt,
                          finRepo:     _finRepo,
                          onTap:       () => _onSelect(_customers[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    if (_totalCount == 0) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.people_outline, size: 56, color: AppColors.textTertiary),
            const SizedBox(height: 16),
            Text(
              'Base de clientes vazia',
              style: AppTypography.cardTitle.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            Text(
              'Sincronize para carregar os clientes do ERP',
              style: AppTypography.body.copyWith(color: AppColors.textTertiary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    return Center(
      child: Text(
        'Nenhum cliente encontrado\npara "$_searchQuery"',
        style: AppTypography.body.copyWith(color: AppColors.textSecondary),
        textAlign: TextAlign.center,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _CustomerTile
// ─────────────────────────────────────────────────────────────────────────────

class _CustomerTile extends StatelessWidget {
  final Customer            customer;
  final NumberFormat        currencyFmt;
  final FinancialRepository finRepo;
  final VoidCallback        onTap;

  const _CustomerTile({
    required this.customer,
    required this.currencyFmt,
    required this.finRepo,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surfacePrimary,
          border: Border(bottom: BorderSide(color: AppColors.divider)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
        child: Row(
          children: [
            // Avatar com inicial
            CircleAvatar(
              radius: 20,
              backgroundColor: AppColors.syncInProgressLight,
              child: Text(
                customer.name.isNotEmpty ? customer.name[0].toUpperCase() : '?',
                style: AppTypography.bodyBold.copyWith(color: AppColors.actionPrimary),
              ),
            ),
            const SizedBox(width: 12),

            // Nome e localização
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    customer.name,
                    style: AppTypography.bodyBold,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    [
                      if (customer.cnpj != null) customer.cnpj!,
                      if (customer.location.isNotEmpty) customer.location,
                    ].join(' · '),
                    style: AppTypography.badge.copyWith(color: AppColors.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // Badge de débitos em aberto (SQLite local)
            _DebtBadge(
              customerId:  customer.id,
              finRepo:     finRepo,
              currencyFmt: currencyFmt,
            ),

            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _DebtBadge — Total de débitos em aberto (dados locais, zero-flicker)
// ─────────────────────────────────────────────────────────────────────────────

class _DebtBadge extends StatelessWidget {
  final String              customerId;
  final FinancialRepository finRepo;
  final NumberFormat        currencyFmt;

  const _DebtBadge({
    required this.customerId,
    required this.finRepo,
    required this.currencyFmt,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<double>(
      future: finRepo.totalOpenByCustomer(customerId),
      builder: (context, snap) {
        // Sem dados ou sem débito: sem widget (evita flicker na lista)
        if (!snap.hasData || snap.data! <= 0) return const SizedBox.shrink();

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color:        Colors.red.shade50,
            borderRadius: BorderRadius.circular(4),
            border:       Border.all(color: Colors.red.shade200),
          ),
          child: Text(
            currencyFmt.format(snap.data!),
            style: AppTypography.badge.copyWith(
              color:      Colors.red.shade700,
              fontFamily: 'RobotoMono',
              fontSize:   10,
            ),
          ),
        );
      },
    );
  }
}

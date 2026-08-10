import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/design/app_colors.dart';
import '../../../../core/design/app_typography.dart';
import '../../../../core/design/app_spacing.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/network/sync_queue_service.dart';
import '../../data/models/customer_model.dart';
import '../../data/repositories/customer_repository_impl.dart';
import 'customer_registration_bottom_sheet.dart';
import 'customer_details_page.dart';

class CustomersPage extends StatefulWidget {
  const CustomersPage({Key? key}) : super(key: key);

  @override
  State<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends State<CustomersPage> {
  final _searchController = TextEditingController();
  final _repository = getIt<CustomerRepositoryImpl>();

  List<CustomerModel> _customers = [];
  bool _isLoading = false;
  int _totalCount = 0;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadInitialCustomers();
    _loadTotalCount();
  }

  Future<void> _loadTotalCount() async {
    final total = await _repository.getCustomerCount();
    if (mounted) {
      setState(() => _totalCount = total);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadInitialCustomers() async {
    setState(() => _isLoading = true);
    // Realiza busca com string vazia para trazer os primeiros
    final results = await _repository.searchLocalCustomers('');
    setState(() {
      _customers = results;
      _isLoading = false;
    });
    _loadTotalCount();
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      setState(() => _isLoading = true);
      final results = await _repository.searchLocalCustomers(query.trim());
      setState(() {
        _customers = results;
        _isLoading = false;
      });
    });
  }

  Future<void> _forceSync() async {
    setState(() => _isLoading = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Forçando sincronização da fila offline...')),
    );
    
    await SyncQueueService.instance.processQueue();
    await _repository.syncCustomers(); // Também tenta atualizar a base de clientes do ERP
    
    await _loadInitialCustomers();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Fila processada e lista atualizada!'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  void _openQuickRegistration() async {
    final result = await CustomerRegistrationBottomSheet.show(context);
    if (result != null) {
      // Se cadastrou com sucesso, recarrega a lista
      _loadInitialCustomers();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text('Clientes ($_totalCount)'),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _forceSync,
            icon: const Icon(Icons.sync),
            tooltip: 'Sincronizar Fila',
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            children: [
              // Barra de pesquisa
              TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'Buscar por Nome, CPF ou Telefone...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            _loadInitialCustomers();
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
                    : _customers.isEmpty
                        ? _buildEmptyState()
                        : ListView.separated(
                            itemCount: _customers.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final customer = _customers[index];
                              final isPending = customer.syncStatus == 'pending';

                              return ListTile(
                                onTap: () {
                                  Navigator.of(context).push(MaterialPageRoute(
                                    builder: (_) => CustomerDetailsPage(customer: customer),
                                  ));
                                },
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.sm,
                                  vertical: AppSpacing.xs,
                                ),
                                leading: CircleAvatar(
                                  backgroundColor: isPending
                                      ? AppColors.warning.withValues(alpha: 0.15)
                                      : const Color(0xFF0F3A70).withValues(alpha: 0.1),
                                  child: Icon(
                                    Icons.person,
                                    color: isPending ? AppColors.warning : const Color(0xFF0F3A70),
                                  ),
                                ),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        customer.name,
                                        style: AppTypography.bodyBold,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (isPending)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppColors.warning.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons.hourglass_empty,
                                              size: 10,
                                              color: AppColors.warning,
                                            ),
                                            const SizedBox(width: 2),
                                            Text(
                                              'OFFLINE',
                                              style: TextStyle(
                                                fontSize: 8,
                                                fontWeight: FontWeight.bold,
                                                color: AppColors.warning,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      customer.cpfCnpj ?? 'Sem Documento',
                                      style: TextStyle(color: Colors.grey.shade600),
                                    ),
                                    if (customer.phone != null)
                                      Text(
                                        customer.phone!,
                                        style: TextStyle(color: Colors.grey.shade600),
                                      ),
                                    if (customer.address != null)
                                      Text(
                                        customer.address!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.grey.shade500,
                                          fontSize: 12,
                                        ),
                                      ),
                                  ],
                                ),
                                trailing: isPending
                                    ? const Icon(Icons.cloud_upload_outlined, color: AppColors.warning)
                                    : const Icon(Icons.cloud_done_outlined, color: AppColors.success),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openQuickRegistration,
        backgroundColor: AppColors.warning,
        foregroundColor: Colors.white,
        tooltip: 'Cadastrar Cliente',
        child: const Icon(Icons.person_add),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.person_search, size: 64, color: Colors.grey.shade300),
        const SizedBox(height: AppSpacing.md),
        Text(
          _searchController.text.isEmpty
              ? 'Nenhum cliente encontrado na base offline.'
              : 'Nenhum cliente corresponde à busca local.',
          style: TextStyle(color: Colors.grey.shade600),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

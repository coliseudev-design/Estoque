import 'package:flutter/material.dart';
import '../../data/models/customer_model.dart';
import '../../data/datasources/customer_local_data_source.dart';
import '../../data/datasources/customer_remote_data_source.dart';
import '../../data/repositories/customer_repository_impl.dart';

class CustomerSearchModal extends StatefulWidget {
  const CustomerSearchModal({Key? key}) : super(key: key);

  static Future<CustomerModel?> show(BuildContext context) {
    return showModalBottomSheet<CustomerModel>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const CustomerSearchModal(),
    );
  }

  @override
  State<CustomerSearchModal> createState() => _CustomerSearchModalState();
}

class _CustomerSearchModalState extends State<CustomerSearchModal> {
  final _searchController = TextEditingController();
  final _repository = CustomerRepositoryImpl(
    CustomerLocalDataSource(),
    CustomerRemoteDataSource(),
  );

  List<CustomerModel> _results = [];
  bool _isLoading = false;

  void _onSearchChanged(String query) async {
    if (query.trim().length < 2) {
      if (_results.isNotEmpty) setState(() => _results.clear());
      return;
    }

    setState(() => _isLoading = true);
    
    // Busca exclusivamente no banco local (offline-first)
    final results = await _repository.searchLocalCustomers(query.trim());
    
    setState(() {
      _results = results;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset, left: 16, right: 16, top: 16),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Container(
              width: 40,
              height: 5,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const Text(
              'Vincular Cliente',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Buscar por Nome, CPF ou Telefone...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _isLoading 
                ? const Center(child: CircularProgressIndicator())
                : _results.isEmpty 
                  ? _buildEmptyState()
                  : ListView.separated(
                      itemCount: _results.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final customer = _results[index];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFF0F3A70).withValues(alpha: 0.1),
                            child: const Icon(Icons.person, color: Color(0xFF0F3A70)),
                          ),
                          title: Text(customer.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(customer.cpfCnpj ?? customer.phone ?? 'Sem contato'),
                          onTap: () {
                            Navigator.of(context).pop(customer);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildEmptyState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.person_search, size: 64, color: Colors.grey.shade300),
        const SizedBox(height: 16),
        Text(
          _searchController.text.isEmpty
            ? 'Digite para buscar um cliente na base offline.'
            : 'Nenhum cliente encontrado localmente.',
          style: TextStyle(color: Colors.grey.shade600),
          textAlign: TextAlign.center,
        )
      ],
    );
  }
}

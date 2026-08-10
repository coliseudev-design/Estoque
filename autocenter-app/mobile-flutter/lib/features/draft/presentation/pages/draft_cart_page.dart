import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/database/database_helper.dart';
import '../../../../core/network/sync_service.dart';
import '../../../vehicle/domain/entities/vehicle.dart';
import '../../domain/entities/draft.dart';
import '../../data/datasources/draft_local_datasource.dart';
import '../../../camera/presentation/providers/camera_session_provider.dart';
import '../../../services/data/datasources/catalog_local_datasource.dart';
import '../../../services/data/datasources/catalog_remote_datasource.dart';
import '../../../services/data/repositories/catalog_repository_impl.dart';
import '../../../services/data/models/catalog_item_model.dart';

class DraftCartPage extends StatefulWidget {
  final Vehicle vehicle;
  final List<String> photosList;

  const DraftCartPage({Key? key, required this.vehicle, required this.photosList}) : super(key: key);

  @override
  State<DraftCartPage> createState() => _DraftCartPageState();
}

class _DraftCartPageState extends State<DraftCartPage> {
  bool _isSaving = false;
  final List<DraftItem> _cartItems = [];

  double get _subtotal {
    return _cartItems.fold(0, (sum, item) => sum + (item.quantity * item.unitPrice) - item.discount);
  }

  void _showAddItemModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) {
        return DraggableScrollableSheet(
          initialChildSize: 0.8,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            final repo = CatalogRepositoryImpl(
              CatalogLocalDataSource(),
              CatalogRemoteDataSource(),
            );

            return Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('Catálogo de Peças e Serviços', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                ),
                Expanded(
                  child: FutureBuilder<List<CatalogItemModel>>(
                    future: repo.getAllCatalog(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (!snapshot.hasData || snapshot.data!.isEmpty) {
                        return const Center(child: Text('Catálogo vazio. Sincronize antes.'));
                      }
                      final items = snapshot.data!;
                      return ListView.builder(
                        controller: scrollController,
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return ListTile(
                            leading: const CircleAvatar(child: Icon(Icons.build_circle)),
                            title: Text(item.name),
                            subtitle: Text('Ref: ${item.erpId} | ${item.category}'),
                            trailing: Text('R\$ ${item.price.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                            onTap: () {
                              _promptQuantityAndConfirm(item);
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      }
    );
  }

  void _promptQuantityAndConfirm(CatalogItemModel item) {
    showDialog(
      context: context,
      builder: (context) {
        final qtdeController = TextEditingController(text: '1');
        return AlertDialog(
          title: Text('Adicionar ${item.name}'),
          content: TextField(
            controller: qtdeController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Quantidade'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () {
                final qtde = double.tryParse(qtdeController.text) ?? 1;
                setState(() {
                  _cartItems.add(DraftItem(
                    draftId: 0,
                    productCode: item.erpId.toString(),
                    productName: item.name,
                    quantity: qtde,
                    unitPrice: item.price,
                    discount: 0,
                  ));
                });
                Navigator.pop(context); // close modal
                 Navigator.pop(context); // close bottom sheet
              },
              child: const Text('Confirmar'),
            ),
          ],
        );
      }
    );
  }

  Future<void> _finishAndSyncDraft() async {
    if (_cartItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('O orçamento precisa de pelo menos 1 serviço ou peça.')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final dbHelper = DatabaseHelper.instance;
      final dataSource = DraftLocalDataSource(dbHelper: dbHelper);
      
      final draft = Draft(
        vehiclePlate: widget.vehicle.plate ?? 'SEM-PLACA',
        customerName: widget.vehicle.customerName ?? 'Balcão',
        status: 'PENDENTE_SYNC',
        createdAt: DateTime.now().toIso8601String(),
      );

      final photos = <DraftPhoto>[];
      for (int i = 0; i < widget.photosList.length; i++) {
        String type;
        if (i == 0) type = 'FRENTE';
        else if (i == 1) type = 'LATERAL_ESQ';
        else if (i == 2) type = 'TRASEIRA';
        else if (i == 3) type = 'LATERAL_DIR';
        else type = 'EXTRA';
        photos.add(DraftPhoto(draftId: 0, path: widget.photosList[i], type: type));
      }

      await dataSource.insertDraft(draft, photos, _cartItems);

      if (mounted) context.read<CameraSessionProvider>().resetSession();

      SyncService.registerOfflineSync();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Atendimento de Pátio Finalizado! A Nuvem cuidará do resto.'), 
          backgroundColor: Colors.green,
          duration: Duration(seconds: 4),
        ),
      );
      
      Navigator.of(context).popUntil((route) => route.isFirst);

    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: Text('Carrinho: ${widget.vehicle.plate}'),
        backgroundColor: const Color(0xFF0F3A70),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_shopping_cart_rounded),
            onPressed: _showAddItemModal,
            tooltip: 'Lançar Código Extra'
          )
        ],
      ),
      body: _isSaving
        ? const Center(child: CircularProgressIndicator(color: Color(0xFFF26822)))
        : Column(
            children: [
              // Photo Summary
              Container(
                color: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    const Icon(Icons.photo_library_outlined, color: Colors.grey),
                    const SizedBox(width: 8),
                    Text('${widget.photosList.length} fotos anexadas do pátio', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              Expanded(
                child: _cartItems.isEmpty 
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.receipt_long_rounded, size: 80, color: Colors.grey.shade300),
                          const SizedBox(height: 16),
                          const Text('Orçamento Vazio', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey)),
                          TextButton(onPressed: _showAddItemModal, child: const Text('Adicionar Primeiro Item')),
                        ],
                      )
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _cartItems.length,
                      itemBuilder: (context, index) {
                        final item = _cartItems[index];
                        final sub = (item.quantity * item.unitPrice) - item.discount;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.blue.shade50,
                              child: const Icon(Icons.build_circle_rounded, color: Colors.blue),
                            ),
                            title: Text(item.productName, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text('${item.quantity}x de R\$ ${item.unitPrice.toStringAsFixed(2)} | Ref: ${item.productCode}'),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('R\$ ${sub.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green)),
                                GestureDetector(
                                  onTap: () => setState(() => _cartItems.removeAt(index)),
                                  child: const Text('Remover', style: TextStyle(color: Colors.red, fontSize: 12)),
                                )
                              ],
                            ),
                          ),
                        );
                      },
                    ),
              ),

              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -4))],
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24))
                ),
                child: SafeArea(
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Total Rascunho', style: TextStyle(fontSize: 16, color: Colors.grey)),
                          Text('R\$ ${_subtotal.toStringAsFixed(2)}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF0F3A70))),
                        ],
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: _cartItems.isEmpty ? null : _finishAndSyncDraft,
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(56),
                          backgroundColor: Colors.green.shade600,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                        ),
                        icon: const Icon(Icons.cloud_upload_rounded),
                        label: const Text('ENVIAR PARA APROVAÇÃO GERENTE', style: TextStyle(fontWeight: FontWeight.bold)),
                      )
                    ],
                  ),
                ),
              )
            ],
          ),
    );
  }
}

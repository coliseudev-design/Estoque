import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../../../../core/design/app_colors.dart';
import '../../../../core/design/app_spacing.dart';
import '../../../../core/design/app_typography.dart';
import '../../../../core/di/injection.dart';
import '../../../customer/data/datasources/customer_local_data_source.dart';
import '../../../customer/data/models/customer_model.dart';
import '../../../customer/presentation/pages/customer_search_modal.dart';
import '../../../customer/presentation/pages/customer_registration_bottom_sheet.dart';
import '../../../services/data/models/catalog_item_model.dart';
import '../../../vehicle/domain/entities/vehicle.dart';
import '../../domain/entities/service_order.dart';
import '../../domain/repositories/service_order_repository.dart';
import 'product_picker_page.dart';
import '../../data/datasources/technician_local_datasource.dart';
import '../../domain/entities/technician.dart';
import '../../../auth/domain/repositories/sellers_repository.dart';
import '../../../auth/data/models/seller_model.dart';
import '../../../../core/network/auth/auth_token_manager.dart';
import '../../../services/data/models/payment_species_model.dart';
import '../../../services/data/models/payment_condition_model.dart';
import '../../../services/data/models/natureza_model.dart';
import '../../../services/data/datasources/catalog_local_datasource.dart';

class OsCreationPage extends StatefulWidget {
  final Vehicle vehicle;
  final double odometer;
  final double fuelLevel;
  final List<ServiceOrderChecklist> checklist;
  final Map<String, String> photoPaths; // photoType -> localPath

  const OsCreationPage({
    Key? key,
    required this.vehicle,
    required this.odometer,
    required this.fuelLevel,
    required this.checklist,
    required this.photoPaths,
  }) : super(key: key);

  @override
  State<OsCreationPage> createState() => _OsCreationPageState();
}

class _OsCreationPageState extends State<OsCreationPage> {
  final _formKey = GlobalKey<FormState>();
  final _complaintsController = TextEditingController();
  final _driverController = TextEditingController();
  
  CustomerModel? _selectedCustomer;
  final List<ServiceOrderItem> _items = [];
  
  DateTime _deliveryDate = DateTime.now().add(const Duration(days: 2));
  bool _isSaving = false;
  List<Technician> _technicians = [];
  List<SellerModel> _sellers = [];
  SellerModel? _selectedSeller;

  List<NaturezaModel> _naturezas = [];
  NaturezaModel? _selectedNatureza;

  List<PaymentSpeciesModel> _species = [];
  PaymentSpeciesModel? _selectedSpecies;

  List<PaymentConditionModel> _conditions = [];
  PaymentConditionModel? _selectedCondition;
  List<PaymentConditionModel> _filteredConditions = [];

  @override
  void initState() {
    super.initState();
    _loadCustomerDetails();
    _loadTechnicians();
    _loadSellers();
    _loadErpConfigurations();
  }

  Future<void> _loadErpConfigurations() async {
    try {
      final db = CatalogLocalDataSource();
      final species = await db.getPaymentSpecies();
      final conditions = await db.getPaymentConditions();
      final naturezas = await db.getNaturezas();

      if (mounted) {
        setState(() {
          _species = species;
          _conditions = conditions;
          _naturezas = naturezas;

          if (species.isNotEmpty) {
            _selectedSpecies = species.first;
            _filterConditionsBySpecies(species.first.id);
          }
          if (naturezas.isNotEmpty) {
            _selectedNatureza = naturezas.first;
          }
        });
      }
    } catch (e) {
      print('Erro ao carregar configuracoes do ERP na OS: $e');
    }
  }

  void _filterConditionsBySpecies(int speciesId) {
    setState(() {
      _filteredConditions = _conditions.where((c) => c.especieId == speciesId).toList();
      _selectedCondition = _filteredConditions.isNotEmpty ? _filteredConditions.first : null;
    });
  }

  Future<void> _loadTechnicians() async {
    final local = TechnicianLocalDataSource();
    final list = await local.getAllTechnicians();
    if (mounted) {
      setState(() {
        _technicians = list;
      });
    }
  }

  Future<void> _loadSellers() async {
    try {
      final repo = getIt<SellersRepository>();
      final list = await repo.getLocalSellers();
      
      final tokenManager = getIt<AuthTokenManager>();
      final activeSellerIdStr = await tokenManager.getVendedorCode();
      SellerModel? activeSeller;
      if (activeSellerIdStr != null) {
        final activeSellerId = int.tryParse(activeSellerIdStr);
        if (activeSellerId != null) {
          try {
            activeSeller = list.firstWhere((s) => s.id == activeSellerId);
          } catch (_) {}
        }
      }

      if (mounted) {
        setState(() {
          _sellers = list;
          _selectedSeller = activeSeller ?? (list.isNotEmpty ? list.first : null);
        });
      }
    } catch (e) {
      print('Erro ao carregar vendedores na OS: $e');
    }
  }

  @override
  void dispose() {
    _complaintsController.dispose();
    _driverController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomerDetails() async {
    if (widget.vehicle.idCliente != null && widget.vehicle.idCliente! > 0) {
      final db = CustomerLocalDataSource();
      final customer = await db.getCustomerByErpId(widget.vehicle.idCliente!);
      if (customer != null && mounted) {
        setState(() {
          _selectedCustomer = customer;
        });
      }
    }
  }

  void _searchCustomer() async {
    final customer = await CustomerSearchModal.show(context);
    if (customer != null && mounted) {
      setState(() {
        _selectedCustomer = customer;
      });
    }
  }

  void _createCustomer() async {
    final customer = await CustomerRegistrationBottomSheet.show(context);
    if (customer != null && mounted) {
      setState(() {
        _selectedCustomer = customer;
      });
    }
  }

  void _addItem() async {
    final CatalogItemModel? selected = await Navigator.of(context).push<CatalogItemModel>(
      MaterialPageRoute(builder: (_) => const ProductPickerPage()),
    );

    if (selected != null && mounted) {
      setState(() {
        final itemId = 'item_${DateTime.now().millisecondsSinceEpoch}_${_items.length}';
        final isService = selected.category.toLowerCase().contains('serviço') ||
            selected.category.toLowerCase().contains('mao de obra');

        _items.add(ServiceOrderItem(
          id: itemId,
          serviceOrderId: '', // Will be assigned on save
          productCode: selected.erpId.toString(),
          productDescription: selected.name,
          quantity: 1.0,
          unitPrice: selected.price,
          totalPrice: selected.price,
          itemType: isService ? 'SERVICE' : 'PART',
          createdAt: DateTime.now().toIso8601String(),
        ));
      });
    }
  }

  void _updateItemQuantity(int index, double quantity) {
    if (quantity <= 0) return;
    setState(() {
      final item = _items[index];
      final newTotal = quantity * item.unitPrice;
      _items[index] = item.copyWith(
        quantity: quantity,
        totalPrice: double.parse(newTotal.toStringAsFixed(2)),
      );
    });
  }

  void _removeItem(int index) {
    setState(() {
      _items.removeAt(index);
    });
  }

  double get _subtotal {
    return _items.fold(0.0, (sum, item) => sum + item.totalPrice);
  }

  Future<String> _getDeviceId() async {
    final info = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final android = await info.androidInfo;
      return android.id;
    } else if (Platform.isIOS) {
      final ios = await info.iosInfo;
      return ios.identifierForVendor ?? 'ios-unknown';
    }
    return 'device-${Platform.operatingSystem}';
  }

  Future<void> _selectDeliveryDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _deliveryDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
    );
    if (picked != null && mounted) {
      setState(() {
        _deliveryDate = picked;
      });
    }
  }

  String _generateUuidV4() {
    final random = Random.secure();
    final chars = '0123456789abcdef';
    String randomHex(int len) {
      return List.generate(len, (_) => chars[random.nextInt(16)]).join();
    }
    final hex8 = randomHex(8);
    final hex4_1 = randomHex(3);
    final hex4_2 = randomHex(3);
    final variantChar = ['8', '9', 'a', 'b'][random.nextInt(4)];
    final hex12 = randomHex(12);
    return '$hex8-${randomHex(4)}-4$hex4_1-$variantChar$hex4_2-$hex12';
  }

  void _saveOs() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedCustomer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vincule um cliente à Ordem de Serviço.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final osId = _generateUuidV4();
      final deviceId = await _getDeviceId();

      // Convert local photos to ServiceOrderPhoto entities
      final List<ServiceOrderPhoto> photos = [];
      widget.photoPaths.forEach((type, path) {
        photos.add(ServiceOrderPhoto(
          id: 'photo_${type.toLowerCase()}_${DateTime.now().millisecondsSinceEpoch}',
          serviceOrderId: osId,
          photoUrl: path, // Local file path
          photoType: type,
          createdAt: DateTime.now().toIso8601String(),
        ));
      });

      // Build complete OS
      final serviceOrder = ServiceOrder(
        id: osId,
        quoteId: null,
        deviceId: deviceId,
        plate: widget.vehicle.plate!,
        customerId: _selectedCustomer?.erpId,
        customerName: _selectedCustomer?.name,
        customerPhone: _selectedCustomer?.phone,
        status: 'ABERTA',
        totalAmount: _subtotal,
        observation: _complaintsController.text.trim(),
        createdAt: DateTime.now().toIso8601String(),
        updatedAt: DateTime.now().toIso8601String(),
        syncStatus: 'pending',
        sellerId: _selectedSeller?.id,
        naturezaId: _selectedNatureza?.id.toString(),
        paymentConditionId: _selectedCondition?.id,
        paymentSpeciesId: _selectedSpecies?.id.toString(),
        driver: _driverController.text.trim().isNotEmpty ? _driverController.text.trim() : null,
        odometer: widget.odometer,
        fuelLevel: widget.fuelLevel,
        items: _items.map((i) => i.copyWith(serviceOrderId: osId)).toList(),
        photos: photos,
        checklist: widget.checklist.map((c) => c.copyWith(serviceOrderId: osId)).toList(),
      );

      final repo = getIt<ServiceOrderRepository>();
      await repo.saveServiceOrderOffline(serviceOrder);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ordem de Serviço criada com sucesso para a placa ${widget.vehicle.plate}!'),
            backgroundColor: AppColors.success,
          ),
        );
        
        // Pop back to initial home scaffold
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar OS offline: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Nova Ordem de Serviço'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              // Vehicle Summary Card
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.directions_car, color: AppColors.primary),
                          const SizedBox(width: 8),
                          Text('Resumo do Veículo', style: AppTypography.bodyBold),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              widget.vehicle.plate ?? '',
                              style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text('${widget.vehicle.brand} ${widget.vehicle.model}', style: AppTypography.bodyBold),
                      Text('Hodômetro: ${widget.odometer.toStringAsFixed(0)} KM • Combustível: ${(widget.fuelLevel * 100).toStringAsFixed(0)}%'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // Customer Selection Section
              Text('Cliente Vinculado *', style: AppTypography.bodyBold),
              const SizedBox(height: AppSpacing.xs),
              if (_selectedCustomer != null)
                Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: AppColors.surfaceMuted,
                      child: Icon(Icons.person, color: AppColors.primary),
                    ),
                    title: Text(_selectedCustomer!.name, style: AppTypography.bodyBold),
                    subtitle: Text('${_selectedCustomer!.cpfCnpj ?? 'Sem Documento'} • ${_selectedCustomer!.phone ?? 'Sem Telefone'}'),
                    trailing: TextButton(
                      onPressed: _searchCustomer,
                      child: const Text('ALTERAR'),
                    ),
                  ),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _searchCustomer,
                        icon: const Icon(Icons.search),
                        label: const Text('BUSCAR CLIENTE'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _createCustomer,
                        icon: const Icon(Icons.person_add),
                        label: const Text('CRIAR RÁPIDO'),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: AppSpacing.md),

              // Seller Selection Section
              Text('Vendedor Responsável *', style: AppTypography.bodyBold),
              const SizedBox(height: AppSpacing.xs),
              DropdownButtonFormField<SellerModel>(
                value: _selectedSeller,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppColors.surfaceMuted,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon: const Icon(Icons.person, color: AppColors.primary),
                ),
                hint: const Text('Selecione o vendedor'),
                items: _sellers.map((seller) {
                  return DropdownMenuItem<SellerModel>(
                    value: seller,
                    child: Text(seller.name),
                  );
                }).toList(),
                onChanged: (val) {
                  setState(() {
                    _selectedSeller = val;
                  });
                },
                validator: (val) => val == null ? 'Selecione o vendedor' : null,
              ),
              const SizedBox(height: AppSpacing.md),

              // Natureza de Operação Dropdown
              Text('Natureza de Operação *', style: AppTypography.bodyBold),
              const SizedBox(height: AppSpacing.xs),
              DropdownButtonFormField<NaturezaModel>(
                value: _selectedNatureza,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppColors.surfaceMuted,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon: const Icon(Icons.assignment, color: AppColors.primary),
                ),
                hint: const Text('Selecione a natureza'),
                items: _naturezas.map((nat) {
                  return DropdownMenuItem<NaturezaModel>(
                    value: nat,
                    child: Text(nat.descricao),
                  );
                }).toList(),
                onChanged: (val) {
                  setState(() {
                    _selectedNatureza = val;
                  });
                },
                validator: (val) => val == null ? 'Selecione a natureza' : null,
              ),
              const SizedBox(height: AppSpacing.md),

              // Espécie de Pagamento Dropdown
              Text('Espécie de Pagamento *', style: AppTypography.bodyBold),
              const SizedBox(height: AppSpacing.xs),
              DropdownButtonFormField<PaymentSpeciesModel>(
                value: _selectedSpecies,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppColors.surfaceMuted,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon: const Icon(Icons.payment, color: AppColors.primary),
                ),
                hint: const Text('Selecione a espécie'),
                items: _species.map((sp) {
                  return DropdownMenuItem<PaymentSpeciesModel>(
                    value: sp,
                    child: Text(sp.description),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _selectedSpecies = val;
                      _filterConditionsBySpecies(val.id);
                    });
                  }
                },
                validator: (val) => val == null ? 'Selecione a espécie' : null,
              ),
              const SizedBox(height: AppSpacing.md),

              // Condição de Pagamento Dropdown
              Text('Condição de Pagamento *', style: AppTypography.bodyBold),
              const SizedBox(height: AppSpacing.xs),
              DropdownButtonFormField<PaymentConditionModel>(
                value: _selectedCondition,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppColors.surfaceMuted,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon: const Icon(Icons.calendar_today, color: AppColors.primary),
                ),
                hint: const Text('Selecione a condição'),
                items: _filteredConditions.map((cond) {
                  return DropdownMenuItem<PaymentConditionModel>(
                    value: cond,
                    child: Text(cond.descricao),
                  );
                }).toList(),
                onChanged: (val) {
                  setState(() {
                    _selectedCondition = val;
                  });
                },
                validator: (val) => val == null ? 'Selecione a condição' : null,
              ),
              // Motorista / Driver field
              Text('Motorista', style: AppTypography.bodyBold),
              const SizedBox(height: AppSpacing.xs),
              TextFormField(
                controller: _driverController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nome do Motorista',
                  prefixIcon: Icon(Icons.person, color: AppColors.primary),
                  hintText: 'Quem está entregando/retirando o veículo...',
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // Complaints / Observation field
              TextFormField(
                controller: _complaintsController,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Reclamações / Diagnóstico Inicial *',
                  alignLabelWithHint: true,
                  hintText: 'Descreva os sintomas descritos pelo cliente ou o problema detectado...',
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) return 'Informe as reclamações ou sintomas.';
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.xl),
              const Divider(),
              const SizedBox(height: AppSpacing.md),

              // Pieces & Services List Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Peças e Serviços', style: AppTypography.headingMedium),
                  ElevatedButton.icon(
                    onPressed: _addItem,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('ADICIONAR', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              if (_items.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.inventory_2_outlined, color: Colors.grey.shade400, size: 40),
                        const SizedBox(height: 8),
                        Text(
                          'Nenhum item adicionado ainda.',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    return Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.productDescription,
                                        style: AppTypography.bodyBold,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        'Código: ${item.productCode} • R\$ ${item.unitPrice.toStringAsFixed(2)}',
                                        style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => _removeItem(index),
                                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                                ),
                              ],
                            ),
                            const Divider(),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    IconButton(
                                      onPressed: () => _updateItemQuantity(index, item.quantity - 1),
                                      icon: const Icon(Icons.remove_circle_outline),
                                    ),
                                    Text(
                                      item.quantity.toStringAsFixed(0),
                                      style: AppTypography.bodyBold,
                                    ),
                                    IconButton(
                                      onPressed: () => _updateItemQuantity(index, item.quantity + 1),
                                      icon: const Icon(Icons.add_circle_outline),
                                    ),
                                  ],
                                ),
                                Text(
                                  'Subtotal: R\$ ${item.totalPrice.toStringAsFixed(2)}',
                                  style: AppTypography.bodyBold.copyWith(color: AppColors.primary),
                                ),
                              ],
                            ),
                            if (_technicians.isNotEmpty) ...[
                              const SizedBox(height: AppSpacing.sm),
                              DropdownButtonFormField<int>(
                                value: item.technicianId,
                                hint: const Text('Selecionar Técnico'),
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Técnico Responsável',
                                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                ),
                                items: _technicians.map((tech) {
                                  return DropdownMenuItem<int>(
                                    value: tech.id,
                                    child: Text(tech.name),
                                  );
                                }).toList(),
                                onChanged: (techId) {
                                  setState(() {
                                    _items[index] = item.copyWith(technicianId: techId);
                                  });
                                },
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
              const SizedBox(height: AppSpacing.xl),
              const Divider(),
              const SizedBox(height: AppSpacing.md),

              // Expected Delivery Date Picker
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_month, color: AppColors.primary),
                title: const Text('Previsão de Entrega'),
                subtitle: Text('${_deliveryDate.day}/${_deliveryDate.month}/${_deliveryDate.year}'),
                trailing: TextButton(
                  onPressed: _selectDeliveryDate,
                  child: const Text('ALTERAR'),
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // Totals
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Valor Total da OS', style: AppTypography.headingMedium),
                  Text(
                    'R\$ ${_subtotal.toStringAsFixed(2)}',
                    style: AppTypography.headingMedium.copyWith(color: AppColors.primary),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxl),

              // Submit Button
              ElevatedButton.icon(
                onPressed: _isSaving ? null : _saveOs,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.warning,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                icon: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: const Text(
                  'SALVAR ORDEM DE SERVIÇO',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }
}

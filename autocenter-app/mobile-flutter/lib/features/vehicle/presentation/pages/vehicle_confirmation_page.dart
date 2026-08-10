import 'package:flutter/material.dart';
import '../../domain/entities/vehicle.dart';
import '../../../draft/presentation/pages/draft_inspection_page.dart';
import '../../../customer/presentation/pages/customer_search_modal.dart';
import '../../../customer/data/datasources/customer_local_data_source.dart';
import '../../../customer/presentation/pages/customer_registration_bottom_sheet.dart';

class VehicleConfirmationPage extends StatefulWidget {
  final Vehicle vehicle;

  const VehicleConfirmationPage({Key? key, required this.vehicle}) : super(key: key);

  @override
  State<VehicleConfirmationPage> createState() => _VehicleConfirmationPageState();
}

class _VehicleConfirmationPageState extends State<VehicleConfirmationPage> {
  late Vehicle _currentVehicle;

  @override
  void initState() {
    super.initState();
    _currentVehicle = widget.vehicle;
    _checkCustomerName();
  }

  void _checkCustomerName() async {
    if (_currentVehicle.idCliente != null && _currentVehicle.idCliente! > 0 && _currentVehicle.customerName == null) {
      final db = CustomerLocalDataSource();
      final c = await db.getCustomerByErpId(_currentVehicle.idCliente!);
      if (c != null && mounted) {
        setState(() {
          _currentVehicle = _currentVehicle.copyWith(customerName: c.name);
        });
      }
    }
  }

  void _vincularCliente() async {
    final customer = await CustomerSearchModal.show(context);
    if (customer != null && mounted) {
      setState(() {
        _currentVehicle = _currentVehicle.copyWith(
          idCliente: customer.erpId,
          customerName: customer.name,
        );
      });
    }
  }

  void _cadastrarNovoCliente() async {
    final customer = await CustomerRegistrationBottomSheet.show(context);
    if (customer != null && mounted) {
      setState(() {
        _currentVehicle = _currentVehicle.copyWith(
          idCliente: customer.erpId,
          customerName: customer.name,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Confirmar Veículo'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.directions_car_filled_rounded,
                size: 80,
                color: Color(0xFF3B82F6), // Theme primary
              ),
              const SizedBox(height: 24),
              Text(
                (_currentVehicle.plate ?? '').toUpperCase(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 32),
              _buildInfoRow('Marca', _currentVehicle.brand ?? 'N/D'),
              const SizedBox(height: 16),
              _buildInfoRow('Modelo', _currentVehicle.model ?? 'N/D'),
              const SizedBox(height: 16),
              _buildInfoRow('Ano', _currentVehicle.anoModelo?.toString() ?? 'N/D'),
              const SizedBox(height: 16),
              
              // Seção de Cliente Adicionada
              if (_currentVehicle.customerName != null && _currentVehicle.customerName!.isNotEmpty)
                 Column(
                   children: [
                     _buildInfoRow(
                       'Cliente Vinculado', 
                       _currentVehicle.customerName!, 
                       isHighlighted: true
                     ),
                     const SizedBox(height: 8),
                     TextButton.icon(
                       onPressed: _vincularCliente,
                       icon: const Icon(Icons.swap_horiz),
                       label: const Text('Alterar Cliente Vinculado'),
                     ),
                   ],
                 )
              else 
                 Column(
                   crossAxisAlignment: CrossAxisAlignment.stretch,
                   children: [
                     Row(
                       children: [
                         Expanded(
                           child: ElevatedButton.icon(
                             onPressed: _vincularCliente,
                             icon: const Icon(Icons.search),
                             label: const Text('Vincular Existente'),
                             style: ElevatedButton.styleFrom(
                               backgroundColor: Colors.blue.shade50,
                               foregroundColor: Colors.blue.shade900,
                               elevation: 0,
                               padding: const EdgeInsets.symmetric(vertical: 16)
                             ),
                           ),
                         ),
                         const SizedBox(width: 12),
                         Expanded(
                           child: ElevatedButton.icon(
                             onPressed: _cadastrarNovoCliente,
                             icon: const Icon(Icons.person_add),
                             label: const Text('Cadastrar Novo'),
                             style: ElevatedButton.styleFrom(
                               backgroundColor: Colors.green.shade50,
                               foregroundColor: Colors.green.shade900,
                               elevation: 0,
                               padding: const EdgeInsets.symmetric(vertical: 16)
                             ),
                           ),
                         ),
                       ],
                     ),
                   ],
                 ),

              const Spacer(),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => DraftInspectionPage(vehicle: _currentVehicle),
                  ));
                },
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Iniciar Orçamento', style: TextStyle(fontSize: 16)),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  // Resets and pops back to the search page.
                  Navigator.of(context).pop();
                },
                style: TextButton.styleFrom(
                  foregroundColor: Colors.red,
                  minimumSize: const Size.fromHeight(56),
                ),
                child: const Text('Cancelar Atendimento', style: TextStyle(fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {bool isHighlighted = false}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isHighlighted ? Colors.blue.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: isHighlighted ? Border.all(color: Colors.blue.shade200) : null,
        boxShadow: isHighlighted ? [] : [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: isHighlighted ? Colors.blue.shade800 : Colors.grey, fontSize: 16)),
          Expanded(
            child: Text(
              value, 
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isHighlighted ? Colors.blue.shade900 : Colors.black)
            ),
          ),
        ],
      ),
    );
  }
}

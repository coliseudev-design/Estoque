import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import '../providers/vehicle_search_provider.dart';
import '../widgets/manual_vehicle_form.dart';
import 'vehicle_confirmation_page.dart';
import '../../../../core/utils/plate_utils.dart';

class VehicleSearchPage extends StatefulWidget {
  const VehicleSearchPage({Key? key}) : super(key: key);

  @override
  State<VehicleSearchPage> createState() => _VehicleSearchPageState();
}

class _VehicleSearchPageState extends State<VehicleSearchPage> {
  final _plateController = TextEditingController();

  @override
  void dispose() {
    _plateController.dispose();
    super.dispose();
  }

  void _search() {
    final plate = _plateController.text.trim();
    if (PlateValidator.isValid(plate)) {
      context.read<VehicleSearchProvider>().searchPlate(plate);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Formato de placa inválido. Use AAA-0000 ou AAA0A00.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Widget _buildSkeletonLoading() {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 60,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            height: 100,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Buscar Veículo'),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: Consumer<VehicleSearchProvider>(
        builder: (context, provider, child) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (provider.status == VehicleSearchStatus.success && provider.vehicle != null) {
              final vehicle = provider.vehicle!;
              provider.reset(); 
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => VehicleConfirmationPage(vehicle: vehicle),
              ));
            } else if (provider.status == VehicleSearchStatus.error && provider.errorMessage != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(provider.errorMessage!),
                  backgroundColor: Colors.redAccent,
                ),
              );
              provider.reset();
            }
          });

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Informe a placa do veículo',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Buscaremos os dados do veículo para iniciar o orçamento.',
                  style: TextStyle(color: Colors.grey, fontSize: 16),
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _plateController,
                  decoration: const InputDecoration(
                    labelText: 'Placa',
                    hintText: 'AAA-0A00 ou AAA-0000',
                    prefixIcon: Icon(Icons.pin_outlined),
                    border: OutlineInputBorder(),
                  ),
                  inputFormatters: [PlateInputFormatter()],
                  textCapitalization: TextCapitalization.characters,
                ),
                const SizedBox(height: 24),
                
                if (provider.status == VehicleSearchStatus.loading)
                  _buildSkeletonLoading()
                else if (provider.status != VehicleSearchStatus.manualFallback)
                  ElevatedButton(
                    onPressed: _search,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                      backgroundColor: const Color(0xFF0F3A70),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Consultar Placa no ERP', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),

                if (provider.status == VehicleSearchStatus.manualFallback)
                  AnimatedOpacity(
                    opacity: 1.0,
                    duration: const Duration(milliseconds: 300),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 24.0),
                      child: ManualVehicleForm(
                        searchedPlate: _plateController.text,
                        onSubmit: (vehicle) {
                          provider.saveManualVehicle(vehicle);
                        },
                      ),
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

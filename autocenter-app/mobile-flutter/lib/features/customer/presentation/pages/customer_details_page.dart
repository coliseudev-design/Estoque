import 'package:flutter/material.dart';
import '../../../../core/design/app_colors.dart';
import '../../../../core/design/app_spacing.dart';
import '../../../../core/design/app_typography.dart';
import '../../../../core/di/injection.dart';
import '../../../vehicle/domain/entities/vehicle.dart';
import '../../../vehicle/domain/repositories/vehicle_repository.dart';
import '../../../vehicle/presentation/pages/vehicle_confirmation_page.dart';
import '../../data/models/customer_model.dart';

class CustomerDetailsPage extends StatefulWidget {
  final CustomerModel customer;

  const CustomerDetailsPage({Key? key, required this.customer}) : super(key: key);

  @override
  State<CustomerDetailsPage> createState() => _CustomerDetailsPageState();
}

class _CustomerDetailsPageState extends State<CustomerDetailsPage> {
  final _vehicleRepository = getIt<VehicleRepository>();
  List<Vehicle> _vehicles = [];
  bool _isLoadingVehicles = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadCustomerVehicles();
  }

  Future<void> _loadCustomerVehicles() async {
    if (widget.customer.erpId == null) {
      // Cliente offline/pending não possui veículos no ERP ainda
      return;
    }

    setState(() {
      _isLoadingVehicles = true;
      _errorMessage = null;
    });

    try {
      final list = await _vehicleRepository.getVehiclesByCustomerId(widget.customer.erpId!);
      if (mounted) {
        setState(() {
          _vehicles = list;
          _isLoadingVehicles = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Falha ao carregar veículos: ${e.toString()}';
          _isLoadingVehicles = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final initials = widget.customer.name.trim().split(' ').take(2).map((s) => s.isNotEmpty ? s[0].toUpperCase() : '').join();

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Ficha do Cliente'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Card
              Card(
                elevation: 0,
                color: Colors.grey.shade50,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 36,
                        backgroundColor: const Color(0xFF0F3A70).withValues(alpha: 0.1),
                        child: Text(
                          initials,
                          style: AppTypography.headingMedium.copyWith(
                            color: const Color(0xFF0F3A70),
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        widget.customer.name,
                        textAlign: TextAlign.center,
                        style: AppTypography.headingMedium.copyWith(fontSize: 20),
                      ),
                      if (widget.customer.fantasyName != null && widget.customer.fantasyName!.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          widget.customer.fantasyName!,
                          textAlign: TextAlign.center,
                          style: AppTypography.body.copyWith(color: Colors.grey.shade600),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.md),
                      _buildChipStatus(),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // Personal Information Section
              Text('Informações Pessoais', style: AppTypography.bodyBold.copyWith(color: AppColors.primary)),
              const SizedBox(height: AppSpacing.xs),
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    children: [
                      _buildDetailRow(Icons.badge, 'CPF / CNPJ', widget.customer.cpfCnpj ?? 'N/D'),
                      const Divider(height: 24),
                      _buildDetailRow(Icons.phone, 'Telefone Principal', widget.customer.phone ?? 'N/D'),
                      if (widget.customer.phone2 != null && widget.customer.phone2!.isNotEmpty) ...[
                        const Divider(height: 24),
                        _buildDetailRow(Icons.phone_android, 'Telefone Secundário', widget.customer.phone2!),
                      ],
                      if (widget.customer.email != null && widget.customer.email!.isNotEmpty) ...[
                        const Divider(height: 24),
                        _buildDetailRow(Icons.email, 'E-mail', widget.customer.email!),
                      ],
                      if (widget.customer.address != null && widget.customer.address!.isNotEmpty) ...[
                        const Divider(height: 24),
                        _buildDetailRow(Icons.location_on, 'Endereço', widget.customer.address!),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // Vehicles Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Veículos Cadastrados', style: AppTypography.bodyBold.copyWith(color: AppColors.primary)),
                  if (_vehicles.isNotEmpty)
                    Text(
                      '${_vehicles.length} veículo(s)',
                      style: AppTypography.caption.copyWith(color: Colors.grey.shade600),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              _buildVehiclesSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChipStatus() {
    final isPending = widget.customer.syncStatus == 'pending';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isPending
            ? AppColors.warning.withValues(alpha: 0.15)
            : AppColors.success.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isPending ? Icons.cloud_upload_outlined : Icons.cloud_done_outlined,
            size: 16,
            color: isPending ? AppColors.warning : AppColors.success,
          ),
          const SizedBox(width: 6),
          Text(
            isPending ? 'Cadastro Offline Pendente' : 'Sincronizado com ERP',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isPending ? AppColors.warning : AppColors.success,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Colors.grey.shade400, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: AppTypography.body,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVehiclesSection() {
    if (widget.customer.erpId == null) {
      return _buildEmptyVehiclesState('Clientes cadastrados offline precisam ser sincronizados com o ERP antes de carregar seus veículos.');
    }

    if (_isLoadingVehicles) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.xl),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_errorMessage != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            children: [
              Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _loadCustomerVehicles,
                child: const Text('Tentar Novamente'),
              )
            ],
          ),
        ),
      );
    }

    if (_vehicles.isEmpty) {
      return _buildEmptyVehiclesState('Nenhum veículo cadastrado na ficha deste cliente no ERP.');
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _vehicles.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (context, index) {
        final vehicle = _vehicles[index];
        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3B82F6).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.directions_car, color: Color(0xFF3B82F6)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${vehicle.brand ?? ''} ${vehicle.model ?? ''}'.trim(),
                            style: AppTypography.bodyBold,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            (vehicle.plate ?? '').toUpperCase(),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade700,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildVehicleInfoChip('Ano', vehicle.anoModelo?.toString() ?? 'N/D'),
                    _buildVehicleInfoChip('Cor', vehicle.cor ?? 'N/D'),
                    _buildVehicleInfoChip('Combustível', vehicle.combustivel ?? 'N/D'),
                  ],
                ),
                if (vehicle.obs != null && vehicle.obs!.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Obs: ${vehicle.obs!}',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () {
                    // Copia o nome do cliente para repassar à tela de confirmação
                    final v = vehicle.copyWith(
                      customerName: widget.customer.name,
                    );
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => VehicleConfirmationPage(vehicle: v),
                    ));
                  },
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Iniciar Atendimento'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3B82F6),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildVehicleInfoChip(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildEmptyVehiclesState(String text) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          children: [
            Icon(Icons.directions_car_outlined, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              text,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

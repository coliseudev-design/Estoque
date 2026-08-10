import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/design/app_colors.dart';
import '../../../../core/design/app_spacing.dart';
import '../../../../core/design/app_typography.dart';
import '../../../vehicle/domain/entities/vehicle.dart';
import '../../domain/entities/service_order.dart';
import 'os_creation_page.dart';

class OsEntryChecklistPage extends StatefulWidget {
  final Vehicle vehicle;

  const OsEntryChecklistPage({Key? key, required this.vehicle}) : super(key: key);

  @override
  State<OsEntryChecklistPage> createState() => _OsEntryChecklistPageState();
}

class _OsEntryChecklistPageState extends State<OsEntryChecklistPage> {
  final _formKey = GlobalKey<FormState>();
  final _odometerController = TextEditingController();
  
  double _fuelLevel = 0.5; // Default to half tank

  // Checklist items
  final Map<String, String> _checklistStatuses = {
    'Ar Condicionado': 'OK',
    'Estepe & Macaco': 'OK',
    'Rádio / Multimídia': 'OK',
    'Luzes & Faróis': 'OK',
    'Nível de Óleo': 'OK',
    'Fluido de Freio': 'OK',
    'Pneus': 'OK',
  };

  final Map<String, String?> _checklistObservations = {
    'Ar Condicionado': '',
    'Estepe & Macaco': '',
    'Rádio / Multimídia': '',
    'Luzes & Faróis': '',
    'Nível de Óleo': '',
    'Fluido de Freio': '',
    'Pneus': '',
  };

  // Required photos
  final Map<String, String?> _photos = {
    'FRONT': null,
    'LEFT': null,
    'RIGHT': null,
    'REAR': null,
  };

  final _imagePicker = ImagePicker();

  @override
  void dispose() {
    _odometerController.dispose();
    super.dispose();
  }

  Future<void> _capturePhoto(String photoType) async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 70, // Compresses to save bandwidth
      );

      if (image != null) {
        setState(() {
          _photos[photoType] = image.path;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao abrir a câmera: $e'), backgroundColor: Colors.red),
      );
    }
  }

  bool _areAllPhotosCaptured() {
    return _photos.values.every((path) => path != null);
  }

  void _proceed() {
    if (!_formKey.currentState!.validate()) return;

    if (!_areAllPhotosCaptured()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor, tire todas as 4 fotos obrigatórias (Frente, Lateral Esq., Lateral Dir. e Traseira).'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    // Map checklists to domain objects
    final List<ServiceOrderChecklist> checklistItems = [];
    _checklistStatuses.forEach((itemName, status) {
      checklistItems.add(ServiceOrderChecklist(
        id: '', // Will be assigned on creation/sync
        serviceOrderId: '', 
        itemName: itemName,
        status: status,
        observation: _checklistObservations[itemName],
        createdAt: DateTime.now().toIso8601String(),
        updatedAt: DateTime.now().toIso8601String(),
      ));
    });

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OsCreationPage(
          vehicle: widget.vehicle,
          odometer: double.parse(_odometerController.text.trim()),
          fuelLevel: _fuelLevel,
          checklist: checklistItems,
          photoPaths: Map<String, String>.from(_photos),
        ),
      ),
    );
  }

  String _getFuelText(double val) {
    if (val == 0.0) return 'Vazio (0%)';
    if (val < 0.25) return 'Quase Vazio';
    if (val == 0.25) return '1/4 de Tanque';
    if (val < 0.5) return 'Menos de Meio Tanque';
    if (val == 0.5) return 'Meio Tanque (50%)';
    if (val < 0.75) return 'Mais de Meio Tanque';
    if (val == 0.75) return '3/4 de Tanque';
    if (val < 1.0) return 'Quase Cheio';
    return 'Tanque Cheio (100%)';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Vistoria & Checklist'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Text('Veículo: ${widget.vehicle.plate} • ${widget.vehicle.brand} ${widget.vehicle.model}',
                  style: AppTypography.bodyBold.copyWith(color: AppColors.textSecondary)),
              const SizedBox(height: AppSpacing.md),
              const Divider(),
              const SizedBox(height: AppSpacing.md),

              // Odometer Reading
              TextFormField(
                controller: _odometerController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Quilometragem (KM) *',
                  prefixIcon: Icon(Icons.speed),
                  hintText: 'Digite o valor do hodômetro...',
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) return 'Informe a quilometragem.';
                  if (double.tryParse(val) == null) return 'Digite um número válido.';
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.xl),

              // Fuel Level
              Text('Nível de Combustível', style: AppTypography.bodyBold),
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  const Icon(Icons.local_gas_station, color: AppColors.primary),
                  Expanded(
                    child: Slider(
                      value: _fuelLevel,
                      min: 0.0,
                      max: 1.0,
                      divisions: 4,
                      onChanged: (val) => setState(() => _fuelLevel = val),
                    ),
                  ),
                ],
              ),
              Center(
                child: Text(
                  _getFuelText(_fuelLevel),
                  style: AppTypography.bodyBold.copyWith(color: AppColors.primary),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              const Divider(),
              const SizedBox(height: AppSpacing.md),

              // Photos Section
              Text('Fotos Obrigatórias (Mínimo 4)', style: AppTypography.headingMedium),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Tire fotos do veículo nos 4 ângulos principais para o laudo.',
                style: AppTypography.body.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.lg),

              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                childAspectRatio: 1.2,
                mainAxisSpacing: AppSpacing.md,
                crossAxisSpacing: AppSpacing.md,
                children: [
                  _buildPhotoSlot('FRONT', 'Frente'),
                  _buildPhotoSlot('LEFT', 'Lateral Esq.'),
                  _buildPhotoSlot('RIGHT', 'Lateral Dir.'),
                  _buildPhotoSlot('REAR', 'Traseira'),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              const Divider(),
              const SizedBox(height: AppSpacing.md),

              // Checklist Section
              Text('Checklist de Acessórios', style: AppTypography.headingMedium),
              const SizedBox(height: AppSpacing.lg),

              ..._checklistStatuses.keys.map((itemName) => _buildChecklistItem(itemName)),

              const SizedBox(height: AppSpacing.xxl),

              ElevatedButton.icon(
                onPressed: _proceed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                icon: const Icon(Icons.arrow_forward),
                label: const Text(
                  'AVANÇAR PARA A OS',
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

  Widget _buildPhotoSlot(String type, String label) {
    final path = _photos[type];

    return GestureDetector(
      onTap: () => _capturePhoto(type),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          border: Border.all(
            color: path != null ? AppColors.success : Colors.grey.shade300,
            width: path != null ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: path != null
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(File(path), fit: BoxFit.cover),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: AppColors.success,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.check, color: Colors.white, size: 14),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        color: Colors.black54,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          label,
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ],
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.camera_alt_outlined, color: Colors.grey.shade400, size: 28),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Tirar Foto *',
                      style: TextStyle(color: Colors.grey.shade400, fontSize: 10),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildChecklistItem(String itemName) {
    final status = _checklistStatuses[itemName]!;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(itemName, style: AppTypography.bodyBold),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Expanded(
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'OK', label: Text('OK'), icon: Icon(Icons.check, size: 14)),
                    ButtonSegment(value: 'WARN', label: Text('ATENÇÃO'), icon: Icon(Icons.warning_amber, size: 14)),
                    ButtonSegment(value: 'BAD', label: Text('AVARIADO'), icon: Icon(Icons.error_outline, size: 14)),
                  ],
                  selected: {status},
                  onSelectionChanged: (newSelection) {
                    setState(() {
                      _checklistStatuses[itemName] = newSelection.first;
                    });
                  },
                  style: SegmentedButton.styleFrom(
                    selectedBackgroundColor: status == 'OK'
                        ? AppColors.success.withValues(alpha: 0.15)
                        : status == 'WARN'
                            ? Colors.orange.withValues(alpha: 0.15)
                            : Colors.red.withValues(alpha: 0.15),
                    selectedForegroundColor: status == 'OK'
                        ? AppColors.success
                        : status == 'WARN'
                            ? Colors.orange
                            : Colors.red,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          TextFormField(
            decoration: const InputDecoration(
              hintText: 'Adicionar observação (opcional)...',
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            onChanged: (val) {
              _checklistObservations[itemName] = val.trim();
            },
          ),
        ],
      ),
    );
  }
}

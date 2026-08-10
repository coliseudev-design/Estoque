import 'package:flutter/material.dart';
import '../../domain/entities/vehicle.dart';

class ManualVehicleForm extends StatefulWidget {
  final String searchedPlate;
  final Function(Vehicle) onSubmit;

  const ManualVehicleForm({
    Key? key,
    required this.searchedPlate,
    required this.onSubmit,
  }) : super(key: key);

  @override
  State<ManualVehicleForm> createState() => _ManualVehicleFormState();
}

class _ManualVehicleFormState extends State<ManualVehicleForm> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _brandController;
  late TextEditingController _modelController;
  late TextEditingController _yearController;

  @override
  void initState() {
    super.initState();
    _brandController = TextEditingController();
    _modelController = TextEditingController();
    _yearController = TextEditingController();
  }

  @override
  void dispose() {
    _brandController.dispose();
    _modelController.dispose();
    _yearController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      final vehicle = Vehicle(
        plate: widget.searchedPlate,
        brand: _brandController.text,
        model: _modelController.text,
        anoModelo: int.tryParse(_yearController.text) ?? DateTime.now().year,
      );
      widget.onSubmit(vehicle);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orange),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Por favor, preencha manualmente os dados do veículo.',
                    style: TextStyle(color: Colors.deepOrange),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _brandController,
            decoration: const InputDecoration(labelText: 'Marca'),
            validator: (value) => value!.isEmpty ? 'Campo obrigatório' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _modelController,
            decoration: const InputDecoration(labelText: 'Modelo'),
            validator: (value) => value!.isEmpty ? 'Campo obrigatório' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _yearController,
            decoration: const InputDecoration(labelText: 'Ano'),
            keyboardType: TextInputType.number,
            validator: (value) => value!.isEmpty ? 'Campo obrigatório' : null,
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: _submit,
            child: const Text('Confirmar Veículo'),
          ),
        ],
      ),
    );
  }
}

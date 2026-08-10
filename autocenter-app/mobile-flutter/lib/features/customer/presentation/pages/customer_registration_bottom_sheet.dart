import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../../../../core/design/app_colors.dart';
import '../../../../core/design/app_typography.dart';
import '../../../../core/design/app_spacing.dart';
import '../../../../core/di/injection.dart';
import '../../data/models/customer_model.dart';
import '../../data/repositories/customer_repository_impl.dart';

class CustomerRegistrationBottomSheet extends StatefulWidget {
  const CustomerRegistrationBottomSheet({Key? key}) : super(key: key);

  static Future<CustomerModel?> show(BuildContext context) {
    return showModalBottomSheet<CustomerModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const CustomerRegistrationBottomSheet(),
    );
  }

  @override
  State<CustomerRegistrationBottomSheet> createState() => _CustomerRegistrationBottomSheetState();
}

class _CustomerRegistrationBottomSheetState extends State<CustomerRegistrationBottomSheet> {
  final _formKey = GlobalKey<FormState>();
  
  final _nameController = TextEditingController();
  final _fantasyNameController = TextEditingController();
  final _cpfCnpjController = TextEditingController();
  final _phoneController = TextEditingController();
  final _phone2Controller = TextEditingController();
  final _emailController = TextEditingController();
  final _zipController = TextEditingController();
  final _streetController = TextEditingController();
  final _numberController = TextEditingController();
  final _complementController = TextEditingController();
  final _neighborhoodController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();

  bool _isSaving = false;
  String _lastCheckedCep = '';

  @override
  void initState() {
    super.initState();
    _zipController.addListener(_onCepChanged);
  }

  void _onCepChanged() {
    final cep = _zipController.text.replaceAll(RegExp(r'\D'), '');
    if (cep.length == 8 && cep != _lastCheckedCep) {
      _lastCheckedCep = cep;
      _searchCep();
    }
  }

  Future<void> _searchCep() async {
    final cep = _zipController.text.trim().replaceAll('-', '').replaceAll('.', '');
    if (cep.length != 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('CEP inválido. Deve conter 8 algarismos.')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final response = await Dio().get('https://viacep.com.br/ws/$cep/json/');
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        if (data['erro'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('CEP não encontrado.')),
          );
        } else {
          setState(() {
            _streetController.text = data['logradouro'] ?? '';
            _neighborhoodController.text = data['bairro'] ?? '';
            _cityController.text = data['localidade'] ?? '';
            _stateController.text = data['uf'] ?? '';
          });
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao consultar CEP: $e')),
      );
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    _zipController.removeListener(_onCepChanged);
    _nameController.dispose();
    _fantasyNameController.dispose();
    _cpfCnpjController.dispose();
    _phoneController.dispose();
    _phone2Controller.dispose();
    _emailController.dispose();
    _zipController.dispose();
    _streetController.dispose();
    _numberController.dispose();
    _complementController.dispose();
    _neighborhoodController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final customer = CustomerModel(
        erpId: null, // Sincronização offline-first irá gerar o ID no ERP
        name: _nameController.text.trim(),
        fantasyName: _fantasyNameController.text.trim().isEmpty ? null : _fantasyNameController.text.trim(),
        cpfCnpj: _cpfCnpjController.text.trim().isEmpty ? null : _cpfCnpjController.text.trim(),
        phone: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
        phone2: _phone2Controller.text.trim().isEmpty ? null : _phone2Controller.text.trim(),
        email: _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
        zip: _zipController.text.trim().isEmpty ? null : _zipController.text.trim(),
        street: _streetController.text.trim().isEmpty ? null : _streetController.text.trim(),
        number: _numberController.text.trim().isEmpty ? null : _numberController.text.trim(),
        complement: _complementController.text.trim().isEmpty ? null : _complementController.text.trim(),
        neighborhood: _neighborhoodController.text.trim().isEmpty ? null : _neighborhoodController.text.trim(),
        city: _cityController.text.trim().isEmpty ? null : _cityController.text.trim(),
        state: _stateController.text.trim().isEmpty ? null : _stateController.text.trim().toUpperCase(),
        address: _buildFullAddress(),
        active: true,
        syncStatus: 'pending',
      );

      final repo = getIt<CustomerRepositoryImpl>();
      await repo.saveCustomerOffline(customer);

      if (mounted) {
        Navigator.of(context).pop(customer);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cliente "${customer.name}" salvo e enfileirado para sincronização.'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar cliente offline: $e'),
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

  String _buildFullAddress() {
    final parts = <String>[];
    if (_streetController.text.trim().isNotEmpty) parts.add(_streetController.text.trim());
    if (_numberController.text.trim().isNotEmpty) parts.add('Nº ${_numberController.text.trim()}');
    if (_complementController.text.trim().isNotEmpty) parts.add(_complementController.text.trim());
    if (_neighborhoodController.text.trim().isNotEmpty) parts.add(_neighborhoodController.text.trim());
    if (_cityController.text.trim().isNotEmpty) parts.add(_cityController.text.trim());
    if (_stateController.text.trim().isNotEmpty) parts.add(_stateController.text.trim().toUpperCase());
    return parts.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(
        bottom: bottomInset,
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.lg,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: Column(
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 5,
              margin: const EdgeInsets.only(bottom: AppSpacing.md),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            Row(
              children: [
                const Icon(Icons.person_add_alt_1, color: AppColors.warning),
                const SizedBox(width: 8),
                Text('Cadastrar Novo Cliente', style: AppTypography.headingMedium),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const Divider(),
            Expanded(
              child: Form(
                key: _formKey,
                child: ListView(
                  children: [
                    const SizedBox(height: AppSpacing.sm),
                    TextFormField(
                      controller: _nameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Nome Completo *',
                        prefixIcon: Icon(Icons.person),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Por favor, insira o nome completo.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextFormField(
                      controller: _fantasyNameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Nome Fantasia / Apelido',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _cpfCnpjController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'CPF / CNPJ',
                              prefixIcon: Icon(Icons.credit_card),
                              hintText: '000.000.000-00',
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: TextFormField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(
                              labelText: 'Telefone Principal',
                              prefixIcon: Icon(Icons.phone),
                              hintText: '(67) 99999-9999',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _phone2Controller,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(
                              labelText: 'Telefone Secundário',
                              prefixIcon: Icon(Icons.phone),
                              hintText: '(67) 99999-9999',
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(
                              labelText: 'E-mail',
                              prefixIcon: Icon(Icons.email),
                              hintText: 'exemplo@email.com',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Text('Endereço', style: AppTypography.bodyBold.copyWith(color: AppColors.primary)),
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: _zipController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'CEP',
                              prefixIcon: const Icon(Icons.map),
                              hintText: '00000-000',
                              suffixIcon: IconButton(
                                icon: const Icon(Icons.search),
                                onPressed: _searchCep,
                                tooltip: 'Buscar CEP',
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          flex: 3,
                          child: TextFormField(
                            controller: _streetController,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(
                              labelText: 'Logradouro / Rua',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _numberController,
                            decoration: const InputDecoration(
                              labelText: 'Número',
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: TextFormField(
                            controller: _complementController,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(
                              labelText: 'Complemento',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextFormField(
                      controller: _neighborhoodController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Bairro',
                        prefixIcon: Icon(Icons.home_outlined),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextFormField(
                            controller: _cityController,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(
                              labelText: 'Cidade',
                              prefixIcon: Icon(Icons.location_city),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          flex: 1,
                          child: TextFormField(
                            controller: _stateController,
                            maxLength: 2,
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(
                              labelText: 'UF',
                              counterText: '',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    ElevatedButton.icon(
                      onPressed: _isSaving ? null : _save,
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
                        'SALVAR CADASTRO (OFFLINE)',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../../../../core/network/auth/auth_token_manager.dart';
import '../../../../core/di/injection.dart';
import '../../domain/repositories/sellers_repository.dart';
import '../../data/models/seller_model.dart';

enum AuthState { idle, loading, success, error }

class AuthProvider extends ChangeNotifier {
  final SellersRepository sellersRepository;
  final AuthTokenManager tokenManager;
  
  AuthState _state = AuthState.idle;
  AuthState get state => _state;
  
  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  List<SellerModel> _sellers = [];
  List<SellerModel> get sellers => _sellers;

  SellerModel? _selectedSeller;
  SellerModel? get selectedSeller => _selectedSeller;

  String _currentPin = '';
  String get currentPin => _currentPin;

  AuthProvider({
    required this.sellersRepository,
    required this.tokenManager,
  });

  void selectSeller(SellerModel? seller) {
    _selectedSeller = seller;
    _currentPin = '';
    notifyListeners();
  }

  void appendDigit(String digit) {
    if (_currentPin.length < 6) {
      _currentPin += digit;
      notifyListeners();
    }
  }

  void removeLastDigit() {
    if (_currentPin.isNotEmpty) {
      _currentPin = _currentPin.substring(0, _currentPin.length - 1);
      notifyListeners();
    }
  }

  void clearPin() {
    _currentPin = '';
    notifyListeners();
  }

  Future<void> loadSellers() async {
    _state = AuthState.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      String? syncError;
      // Tenta sincronizar primeiro para obter novos cadastros/alterações de senhas
      try {
        await sellersRepository.syncSellers();
      } catch (e) {
        print('[AuthProvider] Falha ao sincronizar vendedores da API, usando cache local: $e');
        syncError = e.toString().replaceFirst('Exception: ', '');
      }

      _sellers = await sellersRepository.getLocalSellers();
      if (_sellers.isNotEmpty) {
        // Se houver apenas um vendedor, já deixa selecionado
        _selectedSeller = _sellers.length == 1 ? _sellers.first : null;
        _state = AuthState.idle;
      } else {
        _state = AuthState.error;
        _errorMessage = syncError ?? 'Nenhum vendedor cadastrado. Sincronize com o ERP.';
      }
      notifyListeners();
    } catch (e) {
      _state = AuthState.error;
      _errorMessage = 'Erro ao carregar vendedores: $e';
      notifyListeners();
    }
  }

  Future<bool> loginWithPin() async {
    if (_selectedSeller == null) {
      _state = AuthState.error;
      _errorMessage = 'Selecione um vendedor.';
      notifyListeners();
      return false;
    }

    _state = AuthState.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      final dbPin = _selectedSeller!.pin;
      
      // Valida o PIN inserido
      // Nota: Caso esteja em branco no ERP/Banco, permite entrar com qualquer valor ou PIN vazio.
      if (dbPin != null && dbPin.isNotEmpty && dbPin != _currentPin) {
        _state = AuthState.error;
        _errorMessage = 'PIN incorreto. Tente novamente.';
        _currentPin = '';
        notifyListeners();
        return false;
      }

      // Salva sessão local no SecureStorage
      await tokenManager.saveVendedorCode(_selectedSeller!.id.toString());
      await tokenManager.saveVendedorName(_selectedSeller!.name);

      _state = AuthState.success;
      _currentPin = '';
      notifyListeners();
      return true;
    } catch (e) {
      _state = AuthState.error;
      _errorMessage = 'Falha ao processar login local: $e';
      _currentPin = '';
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    await tokenManager.clearVendedor();
    _selectedSeller = null;
    _currentPin = '';
    _state = AuthState.idle;
    notifyListeners();
  }
}

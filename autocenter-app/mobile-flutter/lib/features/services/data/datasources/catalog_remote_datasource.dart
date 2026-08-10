import 'package:dio/dio.dart';
import '../../../../../core/network/api_client.dart';
import '../../../../../core/di/injection.dart';
import '../models/catalog_item_model.dart';
import '../models/payment_species_model.dart';
import '../models/payment_condition_model.dart';
import '../models/natureza_model.dart';

class CatalogRemoteDataSource {
  final Dio _dio;

  CatalogRemoteDataSource({Dio? dio})
      : _dio = dio ?? (getIt.isRegistered<ApiClient>() ? getIt<ApiClient>().instance : ApiClient().instance);

  Future<List<CatalogItemModel>> pullCatalog() async {
    try {
      final response = await _dio.get('catalog');
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data['data'];
        return data.map((e) => CatalogItemModel.fromMap(e as Map<String, dynamic>)).toList();
      }
      throw Exception('Erro ao buscar catálogo: código de status ${response.statusCode}');
    } on DioException catch (e) {
      print("[CatalogRemote] DioException: ${e.message}");
      throw Exception('Erro de conexão com servidor: ${e.response?.statusCode} - ${e.response?.data ?? e.message}');
    } catch (e) {
      print("[CatalogRemote] Erro geral: $e");
      throw Exception('Erro ao processar catálogo: $e');
    }
  }

  Future<List<PaymentSpeciesModel>> pullPaymentSpecies() async {
    try {
      final response = await _dio.get('payment-species');
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data['data'];
        return data.map((e) => PaymentSpeciesModel.fromMap(e as Map<String, dynamic>)).toList();
      }
      throw Exception('Erro ao buscar espécies: código de status ${response.statusCode}');
    } catch (e) {
      print("[CatalogRemote] Erro pullPaymentSpecies: $e");
      return [];
    }
  }

  Future<List<PaymentConditionModel>> pullPaymentConditions() async {
    try {
      final response = await _dio.get('payment-conditions');
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data['data'];
        return data.map((e) => PaymentConditionModel.fromMap(e as Map<String, dynamic>)).toList();
      }
      throw Exception('Erro ao buscar condições: código de status ${response.statusCode}');
    } catch (e) {
      print("[CatalogRemote] Erro pullPaymentConditions: $e");
      return [];
    }
  }

  Future<List<NaturezaModel>> pullNaturezas() async {
    try {
      final response = await _dio.get('naturezas');
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data['data'];
        return data.map((e) => NaturezaModel.fromMap(e as Map<String, dynamic>)).toList();
      }
      throw Exception('Erro ao buscar naturezas: código de status ${response.statusCode}');
    } catch (e) {
      print("[CatalogRemote] Erro pullNaturezas: $e");
      return [];
    }
  }
}

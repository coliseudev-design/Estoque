import 'package:dio/dio.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/di/injection.dart';

import '../../domain/entities/draft.dart';

class DraftRemoteDataSource {
  final ApiClient apiClient;

  DraftRemoteDataSource({ApiClient? client})
      : apiClient = client ?? (getIt.isRegistered<ApiClient>() ? getIt<ApiClient>() : ApiClient());

  Future<String?> pushDraft(Draft draft, List<DraftItem> items) async {
    try {
      final dio = apiClient.instance;

      final payload = {
        "plate": draft.vehiclePlate,
        "customerName": draft.customerName ?? 'Balcão',
        "items": items.map((i) => {
          "productCode": i.productCode,
          "productDescription": i.productName,
          "quantity": i.quantity,
          "unitPrice": i.unitPrice,
          "itemType": "PART"
        }).toList()
      };

      final response = await dio.post('quotes', data: payload);
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        return response.data['id'] as String?;
      }
      return null;
    } catch (e) {
      if (e.toString().contains('409')) {
         print('[DraftRemote] Erro 409: Draft já em edição ou duplicado');
         return '409_DUPLICADO'; // flag especial para sair da fila
      }
      print('[DraftRemoteDataSource] Falha ao enviar Draft: \$e');
      return null;
    }
  }

  Future<bool> pushPhotos(String quoteId, List<String> photoPaths) async {
    if (photoPaths.isEmpty) return true;
    try {
      final dio = apiClient.instance;
      
      var formData = FormData.fromMap({});
      for (var path in photoPaths) {
         formData.files.add(MapEntry(
           'files[]',
           await MultipartFile.fromFile(path)
         ));
      }

      final response = await dio.post('quotes/$quoteId/photos', data: formData);
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      print('[DraftRemoteDataSource] Falha ao enviar Fotos: \$e');
      return false; // falha nas fotos, mas o quote passou.
    }
  }

  Future<List<Map<String, dynamic>>> getHistory() async {
    try {
      final dio = apiClient.instance;
      final response = await dio.get('quotes/history');
      
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(response.data);
      }
      return [];
    } catch (e) {
      print('[DraftRemoteDataSource] Falha ao buscar histórico: \$e');
      return [];
    }
  }
}

import '../../data/models/seller_model.dart';

abstract class SellersRepository {
  Future<void> syncSellers();
  Future<List<SellerModel>> getLocalSellers();
  Future<SellerModel?> getSellerById(int id);
}

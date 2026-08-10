import '../../../../core/database/database_helper.dart';
import '../../domain/repositories/sellers_repository.dart';
import '../datasources/sellers_remote_datasource.dart';
import '../models/seller_model.dart';

class SellersRepositoryImpl implements SellersRepository {
  final SellersRemoteDataSource _remoteDataSource;
  final DatabaseHelper _dbHelper;

  SellersRepositoryImpl({
    required SellersRemoteDataSource remoteDataSource,
    required DatabaseHelper dbHelper,
  })  : _remoteDataSource = remoteDataSource,
        _dbHelper = dbHelper;

  @override
  Future<void> syncSellers() async {
    try {
      final sellers = await _remoteDataSource.getSellers();
      final db = await _dbHelper.database;

      await db.transaction((txn) async {
        // Limpa a tabela local e insere a lista atualizada vinda da API
        await txn.delete('sellers');
        for (final seller in sellers) {
          await txn.insert('sellers', seller.toMap());
        }
      });
      print('[SellersRepo] Sincronização de vendedores concluída: ${sellers.length} salvos.');
    } catch (e) {
      print('[SellersRepo] Erro ao sincronizar vendedores: $e');
      rethrow;
    }
  }

  @override
  Future<List<SellerModel>> getLocalSellers() async {
    try {
      final db = await _dbHelper.database;
      final List<Map<String, dynamic>> maps = await db.query(
        'sellers',
        where: 'active = 1',
        orderBy: 'name ASC',
      );

      return maps.map((map) => SellerModel.fromMap(map)).toList();
    } catch (e) {
      print('[SellersRepo] Erro ao buscar vendedores locais: $e');
      return [];
    }
  }

  @override
  Future<SellerModel?> getSellerById(int id) async {
    try {
      final db = await _dbHelper.database;
      final List<Map<String, dynamic>> maps = await db.query(
        'sellers',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      if (maps.isNotEmpty) {
        return SellerModel.fromMap(maps.first);
      }
      return null;
    } catch (e) {
      print('[SellersRepo] Erro ao buscar vendedor por ID: $e');
      return null;
    }
  }
}

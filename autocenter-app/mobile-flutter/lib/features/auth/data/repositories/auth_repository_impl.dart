import '../../../../core/network/auth/auth_token_manager.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_remote_datasource.dart';

class AuthRepositoryImpl implements AuthRepository {
  final AuthRemoteDataSource remoteDataSource;
  final AuthTokenManager tokenManager;

  AuthRepositoryImpl({
    required this.remoteDataSource,
    required this.tokenManager,
  });

  @override
  Future<void> login(String username, String password) async {
    final payload = await remoteDataSource.login(username, password);
    
    final token = payload['token'] as String?;
    if (token != null) {
      await tokenManager.saveToken(token);
      await tokenManager.saveVendedorCode(username);
    }
  }

  @override
  Future<bool> checkAuthStatus() async {
    return await tokenManager.hasToken();
  }

  @override
  Future<void> logout() async {
    await tokenManager.clearAll();
  }

  @override
  Future<bool> allowOfflineCacheLogin() async {
    // Retorna true se houver token cacheado da primeira sincronização (Regra Socratic Gate 2)
    return await tokenManager.hasToken();
  }
}

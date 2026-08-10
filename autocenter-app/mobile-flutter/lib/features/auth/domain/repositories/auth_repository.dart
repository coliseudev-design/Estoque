abstract class AuthRepository {
  Future<void> login(String username, String password);
  Future<bool> checkAuthStatus();
  Future<void> logout();
  Future<bool> allowOfflineCacheLogin();
}

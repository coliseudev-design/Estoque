/// SessionService — Gerencia a sessão ativa do vendedor.
///
/// REGRA (Rule-03): sellerId e companyId NUNCA são parâmetros livres.
/// São extraídos EXCLUSIVAMENTE desta sessão autenticada.
///
/// PIN hasheado com SHA-256 (Rule-07: Higiene de Credenciais).
/// Sessão persiste no SQLite — sobrevive ao restart do app.
library;

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:dio/dio.dart';
import '../database/database_helper.dart';
import '../config/app_config_service.dart';
import '../device/device_id_service.dart';
import 'session_model.dart';


/// Estado possível da sessão.
enum SessionState {
  /// Nenhuma sessão ativa — exibe LoginScreen.
  unauthenticated,

  /// Sessão ativa e válida.
  authenticated,
}

class SessionService {
  final DatabaseHelper _db;
  final DeviceIdService _deviceIdService;
  static const _uuid = Uuid();

  /// Notifier reativo — a UI observa mudanças de estado sem polling.
  final ValueNotifier<SessionState> stateNotifier =
      ValueNotifier(SessionState.unauthenticated);

  SellerSession? _activeSession;

  SessionService({
    required DatabaseHelper db,
    DeviceIdService? deviceIdService,
  })  : _db = db,
        _deviceIdService = deviceIdService ?? DeviceIdService();

  // ─────────────────────────────────────────────────────────────────────────
  // Getters
  // ─────────────────────────────────────────────────────────────────────────

  /// Sessão ativa. Null se não autenticado.
  SellerSession? get activeSession => _activeSession;

  /// True se há uma sessão válida ativa.
  bool get isLoggedIn => _activeSession != null;

  /// ID do vendedor da sessão ativa.
  ///
  /// Throws [StateError] se usado sem sessão — falha explícita é desejada
  /// para não permitir que pedidos sejam criados sem vendedor.
  String get sellerId {
    if (_activeSession == null) throw StateError('Nenhuma sessão ativa.');
    return _activeSession!.sellerId;
  }

  /// Token JWT de Acesso
  String? get accessToken => _activeSession?.accessToken;

  /// ID da empresa da sessão ativa.
  String get companyId {
    if (_activeSession == null) throw StateError('Nenhuma sessão ativa.');
    return _activeSession!.companyId;
  }

  /// Desconto máximo global do vendedor (DESCONTO_MAX do FUNCIONARIOS).
  /// Null significa sem limite configurado.
  double? get sellerMaxDiscount => _activeSession?.maxDiscount;

  /// True se já existe PIN cadastrado para o [sellerId] informado.
  /// Usado pela tela de identificação para detectar primeiro acesso.
  Future<bool> hasPinFor(String sellerId) async {
    final existing = await _findSessionBySellerId(sellerId);
    return existing != null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Inicialização
  // ─────────────────────────────────────────────────────────────────────────

  /// Recupera a sessão persistida no SQLite ao iniciar o app.
  /// Chamar uma vez no setupLocator, antes de runApp.
  Future<void> initialize() async {
    try {
      final session = await _loadActiveSession();
      _activeSession = session;
      stateNotifier.value = session != null
          ? SessionState.authenticated
          : SessionState.unauthenticated;
    } catch (e) {
      debugPrint('[SessionService] Erro na inicialização (esperado na Web): $e');
      _activeSession = null;
      stateNotifier.value = SessionState.unauthenticated;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Login
  // ─────────────────────────────────────────────────────────────────────────

  // ─────────────────────────────────────────────────────────────────────────
  // Login via ERP (modo de produção)
  // ─────────────────────────────────────────────────────────────────────────

  /// Faz login usando os dados da tabela local `sellers` (sincronizada do ERP).
  ///
  /// O PIN é validado diretamente contra o campo `pin` (= MOB_SENHA do Firebird),
  /// que é armazenado em texto claro pelo ERP — comparação direta, offline.
  /// 
  /// Em seguida, troca essas informações por um JWT no Identity API.
  ///
  /// Fluxo:
  /// 1. Busca o vendedor pelo [sellerId] na tabela `sellers`
  /// 2. Compara o [pin] digitado com o `pin` armazenado
  /// 3. Obtem JWT do Coliseu.Identity
  /// 4. Cria/atualiza sessão no SQLite
  ///
  /// @throws [AuthException] se vendedor não encontrado, PIN incorreto ou erro no Identity.
  Future<SellerSession> loginWithERP({
    required String sellerId,
    required String pin,
  }) async {
    if (pin.isEmpty) throw const AuthException('Digite seu PIN.');

    debugPrint('[loginWithERP] sellerId=$sellerId pin=[REDACTED]');

    final db   = await _db.database;
    final rows = await db.query(
      'sellers',
      where: 'id = ?',
      whereArgs: [sellerId],
      limit: 1,
    );

    debugPrint('[loginWithERP] sellers found: ${rows.length}');

    if (rows.isEmpty) {
      throw const AuthException(
        'Vendedor não encontrado. Sincronize o app com o servidor primeiro.',
      );
    }

    final sellerRow  = rows.first;
    final storedPin  = sellerRow['pin'] as String?;
    final sellerName = sellerRow['name'] as String? ?? '';

    debugPrint('[loginWithERP] storedPin=${storedPin != null ? '[SET]' : '[EMPTY]'} sellerName=$sellerName');

    // PIN do ERP armazenado como texto claro (MOB_SENHA) — comparação direta
    if (storedPin == null || storedPin.trim() != pin.trim()) {
      throw const AuthException('PIN incorreto.');
    }

    final erpEmpresaId = sellerRow['erp_empresa_id'] as int?;
    if (erpEmpresaId != null) {
      final config = AppConfigService();
      final activeBranchEmpresaId = await config.getBranchErpEmpresaId();
      if (activeBranchEmpresaId != null && activeBranchEmpresaId != erpEmpresaId) {
        throw const AuthException(
          'Você não tem permissão para acessar esta empresa/filial. '
          'Por favor, selecione a filial correta antes de fazer login.',
        );
      }
    }

    debugPrint('[loginWithERP] PIN ok, checking existing session');

    // Recupera JWT do Device (obtido na SetupScreen)
    String? jwtAccess;
    String? jwtRefresh;
    String tenantId = '1';
    String companyName = 'Coliseu';

    try {
      final config = AppConfigService();
      jwtAccess = await config.getAccessToken();
      jwtRefresh = await config.getRefreshToken();
      tenantId = await config.getTenantId() ?? '1';
      final branchName = await config.getBranchName();
      companyName = (branchName != null && branchName.isNotEmpty)
          ? branchName
          : (await config.getCompanyName() ?? 'Coliseu');
    } catch (e) {
      debugPrint('[loginWithERP] Warning: Failed to load device tokens from config: $e');
    }

    // Cria ou reutiliza sessão local
    final existing = await _findSessionBySellerId(sellerId);
    debugPrint('[loginWithERP] existing session: ${existing != null}');

    if (existing != null) {
      // Atualiza os JWTs da sessão existente
      final updated = SellerSession(
        id:          existing.id,
        sellerId:    existing.sellerId,
        sellerName:  existing.sellerName,
        companyId:   tenantId,
        companyName: companyName,
        pinHash:     existing.pinHash,
        createdAt:   existing.createdAt,
        maxDiscount: existing.maxDiscount,
        accessToken: jwtAccess ?? existing.accessToken,
        refreshToken: jwtRefresh ?? existing.refreshToken,
      );
      await _saveSession(updated);
      _activeSession = updated;
    } else {
      debugPrint('[loginWithERP] creating new session');
      final session = SellerSession(
        id:          _uuid.v4(),
        sellerId:    sellerId,
        sellerName:  sellerName,
        companyId:   tenantId,
        companyName: companyName,
        // Armazena hash do PIN para usos internos (Rule-07)
        pinHash:     SellerSession.hashPin(pin),
        createdAt:   DateTime.now().toIso8601String(),
        accessToken: jwtAccess,
        refreshToken: jwtRefresh,
      );
      debugPrint('[loginWithERP] saving session');
      await _saveSession(session);
      _activeSession = session;
    }

    stateNotifier.value = SessionState.authenticated;
    debugPrint('[loginWithERP] SUCCESS');
    return _activeSession!;
  }

  /// Lista todos os vendedores disponíveis localmente (sincronizados do ERP).
  ///
  /// Usado pelo LoginScreen para exibir a lista de seleção de vendedor.
  Future<List<Map<String, dynamic>>> getLocalSellers() async {
    final db = await _db.database;
    return db.query('sellers', orderBy: 'name ASC');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Login legado (criação manual de sessão — usado em dev/testes)
  // ─────────────────────────────────────────────────────────────────────────

  /// Login manual com dados explícitos (compatibilidade com testes).
  /// Em produção, prefira [loginWithERP].
  Future<SellerSession> login({
    required String sellerId,
    required String sellerName,
    required String companyId,
    required String companyName,
    required String pin,
  }) async {
    if (pin.length < 4) {
      throw const AuthException('PIN deve ter ao menos 4 dígitos.');
    }

    final existing = await _findSessionBySellerId(sellerId);

    if (existing != null) {
      // Vendedor já tem sessão — valida PIN
      if (!existing.validatePin(pin)) {
        throw const AuthException('PIN incorreto.');
      }
      _activeSession = existing;
    } else {
      // Primeiro login: cria sessão com PIN definido agora
      final session = SellerSession(
        id:          _uuid.v4(),
        sellerId:    sellerId,
        sellerName:  sellerName,
        companyId:   companyId,
        companyName: companyName,
        pinHash:     SellerSession.hashPin(pin),
        createdAt:   DateTime.now().toIso8601String(),
      );
      await _saveSession(session);
      _activeSession = session;
    }

    stateNotifier.value = SessionState.authenticated;
    return _activeSession!;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Token Refresh
  // ─────────────────────────────────────────────────────────────────────────

  /// Tenta renovar o Access Token enviando o Refresh Token para a Identity API.
  Future<bool> refreshTokens() async {
    if (_activeSession == null) return false;
    
    final config = AppConfigService();
    final refreshToken = await config.getRefreshToken();
    final identityUrl = await config.getIdentityUrl();
    
    if (refreshToken == null || refreshToken.isEmpty) {
      debugPrint('[refreshTokens] No refresh token available');
      return false;
    }

    try {
      final dio = Dio(BaseOptions(
        baseUrl: identityUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
      ));

      final response = await dio.post('/auth/refresh', data: {
        'refreshToken': refreshToken,
      });

      if (response.statusCode == 200 && response.data != null) {
        final newAccess = response.data['accessToken'];
        final newRefresh = response.data['refreshToken'];
        
        // Salva globalmente
        await config.setAccessToken(newAccess);
        await config.setRefreshToken(newRefresh);
        
        // Atualiza a sessão ativa
        final updated = SellerSession(
          id:          _activeSession!.id,
          sellerId:    _activeSession!.sellerId,
          sellerName:  _activeSession!.sellerName,
          companyId:   _activeSession!.companyId,
          companyName: _activeSession!.companyName,
          pinHash:     _activeSession!.pinHash,
          createdAt:   _activeSession!.createdAt,
          maxDiscount: _activeSession!.maxDiscount,
          accessToken: newAccess,
          refreshToken: newRefresh,
        );
        await _saveSession(updated);
        _activeSession = updated;
        
        debugPrint('[refreshTokens] Tokens refreshed successfully.');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[refreshTokens] Failed to refresh tokens: $e');
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Logout
  // ─────────────────────────────────────────────────────────────────────────

  /// Encerra a sessão ativa.
  ///
  /// NÃO apaga a sessão do SQLite — o PIN continua salvo para
  /// quando o vendedor fizer login novamente.
  Future<void> logout() async {
    _activeSession = null;
    stateNotifier.value = SessionState.unauthenticated;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Reset de PIN
  // ─────────────────────────────────────────────────────────────────────────

  /// Altera o PIN de um vendedor autenticado.
  ///
  /// @param currentPin  PIN atual (validado antes de alterar)
  /// @param newPin      Novo PIN (mínimo 4 dígitos)
  Future<void> changePin({
    required String currentPin,
    required String newPin,
  }) async {
    if (_activeSession == null) throw StateError('Sem sessão ativa.');
    if (!_activeSession!.validatePin(currentPin)) {
      throw const AuthException('PIN atual incorreto.');
    }
    if (newPin.length < 4) {
      throw const AuthException('Novo PIN deve ter ao menos 4 dígitos.');
    }

    final db      = await _db.database;
    final newHash = SellerSession.hashPin(newPin);
    await db.update(
      'seller_sessions',
      {'pin_hash': newHash},
      where: 'id = ?',
      whereArgs: [_activeSession!.id],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Privados — acesso ao SQLite
  // ─────────────────────────────────────────────────────────────────────────

  Future<SellerSession?> _loadActiveSession() async {
    final db   = await _db.database;
    final rows = await db.query(
      'seller_sessions',
      where: 'active = 1',
      limit: 1,
    );
    return rows.isEmpty ? null : SellerSession.fromMap(rows.first);
  }

  Future<SellerSession?> _findSessionBySellerId(String sellerId) async {
    final db   = await _db.database;
    final rows = await db.query(
      'seller_sessions',
      where: 'seller_id = ?',
      whereArgs: [sellerId],
      limit: 1,
    );
    return rows.isEmpty ? null : SellerSession.fromMap(rows.first);
  }

  Future<void> _saveSession(SellerSession session) async {
    final db = await _db.database;
    await db.insert(
      'seller_sessions',
      session.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AuthException
// ─────────────────────────────────────────────────────────────────────────────

/// Exceção de autenticação — mensagem localizável para exibição na UI.
class AuthException implements Exception {
  final String message;
  const AuthException(this.message);

  @override
  String toString() => message;
}

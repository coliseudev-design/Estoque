/// Modelos de sessão do vendedor e de cliente.
///
/// REGRA (Rule-03 Multi-Tenant): sellerId e companyId são extraídos
/// EXCLUSIVAMENTE da sessão local ativa. Nunca de parâmetros de request.
library;

import 'dart:convert';
import 'package:crypto/crypto.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SellerSession
// ─────────────────────────────────────────────────────────────────────────────

/// Sessão ativa de um vendedor no dispositivo.
/// Persiste no SQLite — sobrevive ao restart do app.
class SellerSession {
  final String id;
  final String sellerId;
  final String sellerName;
  final String companyId;
  final String companyName;
  final String pinHash;          // SHA-256 do PIN — nunca o PIN em texto
  final String createdAt;
  final double? maxDiscount;     // DESCONTO_MAX do FUNCIONARIOS (limite global)
  final String? accessToken;
  final String? refreshToken;

  const SellerSession({
    required this.id,
    required this.sellerId,
    required this.sellerName,
    required this.companyId,
    required this.companyName,
    required this.pinHash,
    required this.createdAt,
    this.maxDiscount,
    this.accessToken,
    this.refreshToken,
  });

  factory SellerSession.fromMap(Map<String, dynamic> map) => SellerSession(
    id:           map['id'] as String,
    sellerId:     map['seller_id'] as String,
    sellerName:   map['seller_name'] as String,
    companyId:    map['company_id'] as String,
    companyName:  map['company_name'] as String,
    pinHash:      map['pin_hash'] as String,
    createdAt:    map['created_at'] as String,
    maxDiscount:  (map['max_discount'] as num?)?.toDouble(),
    accessToken:  map['access_token'] as String?,
    refreshToken: map['refresh_token'] as String?,
  );

  Map<String, dynamic> toMap() => {
    'id':           id,
    'seller_id':    sellerId,
    'seller_name':  sellerName,
    'company_id':   companyId,
    'company_name': companyName,
    'pin_hash':     pinHash,
    'created_at':   createdAt,
    'max_discount': maxDiscount,
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'active':       1,
  };

  /// Hash SHA-256 do PIN — nunca armazenar PIN em texto puro (Rule-07).
  ///
  /// @param pin  PIN numérico de 4-6 dígitos
  /// @returns    Hash hex SHA-256 do PIN
  static String hashPin(String pin) {
    final bytes = utf8.encode(pin);
    return sha256.convert(bytes).toString();
  }

  /// Valida se o PIN fornecido corresponde ao hash armazenado.
  bool validatePin(String pin) => pinHash == hashPin(pin);
}

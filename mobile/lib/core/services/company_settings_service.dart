/// CompanySettingsService — Configurações comportamentais da empresa sincronizadas.
///
/// Armazena o `priceTableMode` e `allowNegativeStock` localmente no SQLite
/// e expõe para toda a app. Sincronizado via `SyncService.pullCompanySettings()`.
///
/// Modos possíveis para priceTableMode:
///   "none"    — Preço base sempre, tabelas ignoradas
///   "product" — Tabela do cliente aplicada automaticamente
///   "prompt"  — Vendedor escolhe a tabela ao criar o pedido
///
/// allowNegativeStock:
///   false (padrão) — Produto sem estoque: visual esmaecido, não pode ser adicionado
///   true            — Produto sem estoque: badge laranja, ainda pode ser adicionado
library;

import 'package:get_it/get_it.dart';
import '../database/database_helper.dart';

class CompanySettingsService {
  static const String _tableSettings = 'company_settings';

  String _priceTableMode     = 'none';
  bool   _allowNegativeStock = false;

  /// Modo de tabela de preço atual.
  String get priceTableMode => _priceTableMode;

  /// Retorna true se a empresa usa tabela de preço (qualquer modo ativo).
  bool get usePriceTable => _priceTableMode != 'none';

  /// Retorna true se o vendedor deve escolher a tabela manualmente.
  bool get promptPriceTable => _priceTableMode == 'prompt';

  /// Retorna true se a tabela vinculada ao cliente é aplicada automaticamente.
  bool get autoApplyPriceTable => _priceTableMode == 'product';

  /// Retorna true se a empresa permite vender produtos com estoque zero ou negativo.
  ///
  /// Quando true:  badge laranja "Sem Estoque" mas produto permanece selecionável.
  /// Quando false: produto esmaecido e bloqueado para adição ao carrinho (padrão).
  bool get allowNegativeStock => _allowNegativeStock;

  // ─────────────────────────────────────────────────────────────────────────
  // Persistência SQLite
  // ─────────────────────────────────────────────────────────────────────────

  /// Carrega as configurações salvas localmente.
  /// Deve ser chamado ao iniciar o app (após setupLocator).
  Future<void> load() async {
    try {
      final db = await GetIt.I<DatabaseHelper>().database;
      final rows = await db.query(_tableSettings, limit: 1);
      if (rows.isNotEmpty) {
        _priceTableMode     = rows.first['price_table_mode'] as String? ?? 'none';
        final raw           = rows.first['allow_negative_stock'];
        _allowNegativeStock = raw != null && raw != 0;
      }
    } catch (_) {
      // Tabela pode não existir ainda — usa defaults
    }
  }

  /// Salva as configurações localmente (chamado pelo SyncService após pull).
  ///
  /// @param mode               Um dos valores: "none", "product", "prompt"
  /// @param allowNegativeStock Permite venda de produtos com estoque zero/negativo
  Future<void> save(String mode, {bool allowNegativeStock = false}) async {
    _priceTableMode     = mode;
    _allowNegativeStock = allowNegativeStock;
    try {
      final db = await GetIt.I<DatabaseHelper>().database;
      await db.rawInsert(
        '''
        INSERT INTO $_tableSettings (id, price_table_mode, allow_negative_stock, synced_at)
        VALUES (1, ?, ?, datetime('now'))
        ON CONFLICT(id) DO UPDATE SET
            price_table_mode      = excluded.price_table_mode,
            allow_negative_stock  = excluded.allow_negative_stock,
            synced_at             = excluded.synced_at
        ''',
        [mode, allowNegativeStock ? 1 : 0],
      );
    } catch (_) {
      // Falha silenciosa — continua com valor em memória
    }
  }
}

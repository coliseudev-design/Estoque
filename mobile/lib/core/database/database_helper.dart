/// DatabaseHelper â€” Singleton responsÃ¡vel por toda interaÃ§Ã£o com SQLite.
///
/// Responsabilidades:
/// - Abrir/criar o banco de dados local
/// - Executar migrations versionadas
/// - Prover mÃ©todos CRUD base para todas as entidades
///
/// REGRA: Toda lÃ³gica de negÃ³cio fica nos Services/Repositories.
///        Este arquivo Ã© APENAS infraestrutura de acesso a dados.
library;

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/foundation.dart';

class DatabaseHelper {
  static const String _dbName    = 'coliseu_sales.db';
  // v38: Adiciona erp_empresa_id na tabela sellers para restrição de login
  static const int    _dbVersion = 38;


  // Singleton
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  /// Construtor exclusivo para testes unitÃ¡rios.
  ///
  /// Injeta um [Database] jÃ¡ aberto (tipicamente sqflite_common_ffi em memÃ³ria)
  /// sem executar migrations normais. NÃƒO use em produÃ§Ã£o.
  DatabaseHelper.forTest(Database testDb) : _database = testDb;

  Database? _database;
  Future<Database>? _dbOpenFuture;

  /// Retorna a instância do banco, inicializando se necessário.
  Future<Database> get database async {
    if (kIsWeb) {
      // No simulador Web, retornamos o próprio Helper como dynamic
      // para evitar quebras em chamadas de métodos como query() ou insert().
      // O Dart permitirá chamadas dinâmicas se o tipo de retorno for dynamic.
      return this as dynamic;
    }
    if (_database != null) return _database!;
    _dbOpenFuture ??= _initDatabase();
    _database = await _dbOpenFuture;
    return _database!;
  }


  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (kIsWeb) {
      debugPrint('[DatabaseHelper] Mock call: ${invocation.memberName}');
      
      // Handle transaction()
      if (invocation.memberName == #transaction) {
        final Function callback = invocation.positionalArguments[0];
        // Execute the callback with "this" as the transaction object (recursive mock)
        return Future.value(callback(this));
      }

      // Retorna listas vazias para queries, 0 para inserts/updates
      if (invocation.memberName == #query || invocation.memberName == #rawQuery) {
        return Future.value(<Map<String, dynamic>>[]);
      }
      if (invocation.memberName == #insert || invocation.memberName == #update || invocation.memberName == #delete || invocation.memberName == #execute || invocation.memberName == #rawInsert || invocation.memberName == #rawUpdate || invocation.memberName == #rawDelete) {
        return Future.value(0);
      }
      if (invocation.memberName == #batch) {
        return _MockBatch();
      }
      return Future.value(null);
    }
    return super.noSuchMethod(invocation);
  }


  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // InicializaÃ§Ã£o
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<Database> _initDatabase() async {
    if (kIsWeb) return DatabaseHelper._internal() as dynamic;

    final dbPath = await getDatabasesPath();
    final path   = join(dbPath, _dbName);

    return openDatabase(
      path,
      version: _dbVersion,
      onCreate:  _onCreate,
      onUpgrade: _onUpgrade,
      // WAL mode: melhor concorrÃªncia leitura/escrita
      // foreign_keys: ativa integridade referencial (desabilitada por padrÃ£o no SQLite)
      // WAL mode: melhor concorrÃªncia leitura/escrita
        // foreign_keys: ativa integridade referencial (desabilitada por padrÃ£o no SQLite)
        onOpen: (db) async {
          try {
            await db.rawQuery('PRAGMA journal_mode=WAL');
            await db.rawQuery('PRAGMA foreign_keys=ON');
          } catch (_) {
            // PRAGMA via rawQuery pode falhar em alguns dispositivos â€” nÃ£o Ã© crÃ­tico
          }
        },
    );
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // Wipe de dados (troca de empresa / tenant)
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Remove TODOS os dados locais sem apagar o schema.
  ///
  /// Usado quando o dispositivo troca de empresa: garante que nenhum dado
  /// da empresa anterior fique visÃ­vel para a nova empresa.
  ///
  /// Preserva a estrutura das tabelas â€” apenas executa DELETE FROM em cada uma.
  /// O prÃ³ximo ciclo de sync traz os dados do novo tenant do zero.
  Future<void> clearAllTables() async {
    if (kIsWeb) return; // modo web nÃ£o tem banco real

    final db = await database;

    // Descobre dinamicamente todas as tabelas do usuÃ¡rio (exclui internas do SQLite)
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'android_%'",
    );

    // IMPORTANTE: PRAGMA foreign_keys NÃƒO funciona dentro de transaction no SQLite
    // (Ã© silenciosamente ignorado). Deve ser executado FORA da transaction.
    await db.rawQuery('PRAGMA foreign_keys=OFF');

    try {
      await db.transaction((txn) async {
        for (final row in tables) {
          final tableName = row['name'] as String;
          await txn.delete(tableName);
          debugPrint('[DatabaseHelper] clearAllTables â†’ $tableName limpa');
        }
      });
    } finally {
      // Reabilita FK independentemente de erro (cleanup obrigatÃ³rio)
      await db.rawQuery('PRAGMA foreign_keys=ON');
    }

    debugPrint('[DatabaseHelper] âœ“ Banco local zerado para nova empresa');
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // Schema â€” versÃ£o 1
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> _onCreate(Database db, int version) async {
    await db.transaction((txn) async {
      // Fila de sincronizaÃ§Ã£o â€” coraÃ§Ã£o do sistema offline-first
      await txn.execute('''
        CREATE TABLE sync_queue (
          id           TEXT    PRIMARY KEY,
          entity_type  TEXT    NOT NULL,
          entity_id    TEXT    NOT NULL,
          payload      TEXT    NOT NULL,
          sync_status  TEXT    NOT NULL DEFAULT 'pending',
          created_at   TEXT    NOT NULL,
          retry_count  INTEGER NOT NULL DEFAULT 0,
          error_message TEXT
        )
      ''');

      await txn.execute('''
        CREATE INDEX idx_sq_status ON sync_queue (sync_status)
      ''');

      await txn.execute('''
        CREATE INDEX idx_sq_created ON sync_queue (created_at)
      ''');

      // Pedidos locais â€” schema completo v23 (deve conter TODAS as colunas
      // de todas as migraÃ§Ãµes para que instalaÃ§Ãµes limpas sejam equivalentes
      // ao resultado de _onUpgrade completo).
      await txn.execute('''
        CREATE TABLE orders (
          id                           TEXT    PRIMARY KEY,
          company_id                   TEXT    NOT NULL DEFAULT '1',
          customer_id                  TEXT    NOT NULL,
          customer_name                TEXT    NOT NULL,
          total_amount                 REAL    NOT NULL,
          notes                        TEXT,
          sync_status                  TEXT    NOT NULL DEFAULT 'pending',
          created_at                   TEXT    NOT NULL,
          updated_at                   TEXT    NOT NULL,
          server_confirmed_at          TEXT,
          payment_species_id           TEXT,
          payment_species_name         TEXT,
          payment_condition_id         TEXT,
          payment_condition_name       TEXT,
          payment_days                 INTEGER,
          payment_installments         INTEGER,
          payment_days_per_installment INTEGER,
          payment_entry_days           INTEGER,
          discount_percent             REAL    NOT NULL DEFAULT 0,
          discount_value               REAL    NOT NULL DEFAULT 0,
          natureza_id                  TEXT,
          natureza_descricao           TEXT,
          error_message                TEXT,
          erp_order_id                 TEXT,
          order_discount_input         REAL    NOT NULL DEFAULT 0,
          order_discount_mode          TEXT    NOT NULL DEFAULT 'percent'
        )
      ''');

      await txn.execute('''
        CREATE INDEX idx_orders_status ON orders (sync_status)
      ''');

      await txn.execute('''
        CREATE INDEX idx_orders_created ON orders (created_at DESC)
      ''');

      // Itens de pedido
      await txn.execute('''
        CREATE TABLE order_items (
          id                 TEXT  PRIMARY KEY,
          order_id           TEXT  NOT NULL,
          product_code       TEXT  NOT NULL,
          product_name       TEXT  NOT NULL,
          quantity           REAL  NOT NULL,
          unit_price         REAL  NOT NULL,
          discount           REAL  NOT NULL DEFAULT 0,
          total_price        REAL  NOT NULL,
          discount_mode      TEXT  NOT NULL DEFAULT 'percent',
          raw_discount_input REAL  NOT NULL DEFAULT 0,
          FOREIGN KEY (order_id) REFERENCES orders (id)
        )
      ''');

      await txn.execute('''
        CREATE INDEX idx_oi_order ON order_items (order_id)
      ''');

      // Cache do catÃ¡logo de produtos (pull do ERP)
      await txn.execute('''
        CREATE TABLE products (
          code              TEXT  PRIMARY KEY,
          name              TEXT  NOT NULL,
          name_short        TEXT,
          price             REAL  NOT NULL DEFAULT 0,
          price_min         REAL,
          stock             REAL  NOT NULL DEFAULT 0,
          unit              TEXT,
          brand             TEXT,
          bar_code          TEXT,
          reference         TEXT,
          max_discount      REAL,
          category          TEXT,
          price_cost        REAL,
          erp_depto_padrao  INTEGER,
          last_synced_at    TEXT
        )
      ''');

      await txn.execute('''
        CREATE INDEX idx_products_name ON products (name)
      ''');

      // Metadados de sync (controles internos)
      await txn.execute('''
        CREATE TABLE sync_metadata (
          key   TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )
      ''');

      // Registra timestamps iniciais
      await txn.insert('sync_metadata', {
        'key':   'last_catalog_sync',
        'value': DateTime.fromMillisecondsSinceEpoch(0).toIso8601String(),
      });
      await txn.insert('sync_metadata', {
        'key':   'last_customers_sync',
        'value': DateTime.fromMillisecondsSinceEpoch(0).toIso8601String(),
      });
      await txn.insert('sync_metadata', {
        'key':   'last_sellers_sync',
        'value': DateTime.fromMillisecondsSinceEpoch(0).toIso8601String(),
      });

      // â”€â”€ v2: SessÃµes de vendedor â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
      await txn.execute('''
        CREATE TABLE seller_sessions (
          id            TEXT    PRIMARY KEY,
          seller_id     TEXT    NOT NULL,
          seller_name   TEXT    NOT NULL,
          company_id    TEXT    NOT NULL,
          company_name  TEXT    NOT NULL,
          pin_hash      TEXT    NOT NULL,
          created_at    TEXT    NOT NULL,
          active        INTEGER NOT NULL DEFAULT 1,
          max_discount  REAL,
          access_token  TEXT,
          refresh_token TEXT
        )
      ''');

      await txn.execute('''
        CREATE INDEX idx_sessions_active ON seller_sessions (active)
      ''');

      // â”€â”€ v2: Cache de clientes â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
      await txn.execute('''
        CREATE TABLE customers (
          id             TEXT  PRIMARY KEY,
          name           TEXT  NOT NULL,
          cnpj           TEXT,
          city           TEXT,
          state          TEXT,
          credit_limit   REAL  NOT NULL DEFAULT 0,
          last_synced_at TEXT,
          phone          TEXT,
          email          TEXT,
          street         TEXT,
          street_number  TEXT,
          neighborhood   TEXT,
          zip_code       TEXT,
          seller_id      TEXT,
          price_table_id TEXT
        )
      ''');

      await txn.execute('''
        CREATE INDEX idx_customers_name ON customers (name)
      ''');

      // â”€â”€ v3: Cache de vendedores (FUNCIONARIOS WHERE MOB_ACESSO=1) â”€â”€â”€â”€â”€â”€
      await txn.execute('''
        CREATE TABLE sellers (
          id             TEXT  PRIMARY KEY,
          mobile_id      TEXT,
          name           TEXT  NOT NULL,
          email          TEXT,
          pin            TEXT,
          max_discount   REAL,
          commission     REAL,
          erp_empresa_id INTEGER,
          last_synced_at TEXT
        )
      ''');

      // â”€â”€ v4: Cache de formas de pagamento (ESPECIE_PGTO) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
      await txn.execute('''
        CREATE TABLE payment_species (
          payment_species_id  TEXT  PRIMARY KEY,
          name                TEXT  NOT NULL,
          type                TEXT,
          days                INTEGER,
          last_synced_at      TEXT
        )
      ''');

      // â”€â”€ v4/12: Cache de condiÃ§Ãµes de pagamento (MOB_TABELAFORMASPAGTO) â”€â”€â”€â”€â”€â”€
      await txn.execute('''
        CREATE TABLE payment_conditions (
          id             TEXT PRIMARY KEY,
          descricao      TEXT NOT NULL,
          especie_id     TEXT,
          desconto_max   REAL,
          parcelas       INTEGER,
          dias_entrada   INTEGER,
          dias_parcelas  INTEGER,
          mob_ordem      INTEGER
        )
      ''');

      // â”€â”€ v4: Cache de naturezas de operaÃ§Ã£o (NATUREZA_OPERACAO) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
      await txn.execute('''
        CREATE TABLE natureza_operacao (
          natureza_id    TEXT  PRIMARY KEY,
          descricao      TEXT  NOT NULL,
          descricao_nota TEXT,
          codigo_fiscal  TEXT,
          es             TEXT,
          mob_ordem      INTEGER,
          last_synced_at TEXT
        )
      ''');

      // â”€â”€ v5: TÃ­tulos financeiros do cliente â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
      await txn.execute('''
        CREATE TABLE financials (
          id                  TEXT PRIMARY KEY,
          customer_id         TEXT NOT NULL,
          doc_number          TEXT,
          amount              REAL NOT NULL DEFAULT 0,
          interest            REAL NOT NULL DEFAULT 0,
          due_date            TEXT,
          payment_species_id  TEXT,
          is_paid             INTEGER NOT NULL DEFAULT 0,
          type                TEXT,
          payment_date        TEXT,
          last_synced_at      TEXT
        )
      ''');
      await txn.execute('CREATE INDEX IF NOT EXISTS idx_fin_customer ON financials (customer_id)');
      await txn.execute('CREATE INDEX IF NOT EXISTS idx_fin_paid ON financials (is_paid)');

      // â”€â”€ v19: KPIs de desempenho reais do ERP (MINHASVENDAS) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
      await txn.execute('''
        CREATE TABLE seller_kpis (
          id                   INTEGER PRIMARY KEY AUTOINCREMENT,
          company_id           TEXT    NOT NULL DEFAULT '1',
          seller_id            TEXT    NOT NULL,
          month                INTEGER NOT NULL,
          year                 INTEGER NOT NULL,
          venda_diaria         REAL    NOT NULL DEFAULT 0,
          venda_mensal         REAL    NOT NULL DEFAULT 0,
          comissao_diaria      REAL    NOT NULL DEFAULT 0,
          comissao_mensal       REAL    NOT NULL DEFAULT 0,
          meta_diaria          REAL    NOT NULL DEFAULT 0,
          meta_mensal          REAL    NOT NULL DEFAULT 0,
          servico_mensal       REAL    NOT NULL DEFAULT 0,
          comissao_sv_mensal   REAL    NOT NULL DEFAULT 0,
          total_diario         REAL    NOT NULL DEFAULT 0,
          total_mensal         REAL    NOT NULL DEFAULT 0,
          comissao_diaria_r    REAL    NOT NULL DEFAULT 0,
          comissao_mensal_r    REAL    NOT NULL DEFAULT 0,
          synced_at            TEXT    NOT NULL
        )
      ''');
      await txn.execute('CREATE INDEX IF NOT EXISTS idx_skpis_seller ON seller_kpis (company_id, seller_id, year, month)');

      // â”€â”€ v20+25: Rankings de vendas do ERP (L_VENDAS_*) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
      // Alimentado pelo Worker (SyncSalesRankingsJob.cs) via Middleware.
      await txn.execute('''
        CREATE TABLE IF NOT EXISTS erp_sales_rankings (
          id                   INTEGER PRIMARY KEY AUTOINCREMENT,
          company_id           TEXT    NOT NULL DEFAULT '1',
          seller_id            TEXT    NOT NULL,
          period               TEXT    NOT NULL DEFAULT 'month',
          month                INTEGER NOT NULL,
          year                 INTEGER NOT NULL,
          top_products_json    TEXT    NOT NULL DEFAULT '[]',
          top_clients_json     TEXT    NOT NULL DEFAULT '[]',
          by_region_json       TEXT    NOT NULL DEFAULT '[]',
          by_seller_json       TEXT    NOT NULL DEFAULT '[]',
          revenue_by_day_json  TEXT    NOT NULL DEFAULT '[]',
          client_health_json   TEXT    NOT NULL DEFAULT '{}',
          category_mix_json    TEXT    NOT NULL DEFAULT '[]',
          heatmap_stats_json   TEXT    NOT NULL DEFAULT '[]',
          synced_at            TEXT    NOT NULL
        )
      ''');
      await txn.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_rankings_seller ON erp_sales_rankings (company_id, seller_id, year, month, period)');

      // â”€â”€ v22: Tabelas de preÃ§o (TABELA_PRECOS) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
      await txn.execute('''
        CREATE TABLE price_tables (
          id          TEXT PRIMARY KEY,
          name        TEXT NOT NULL,
          markup_pct  REAL NOT NULL DEFAULT 0
        )
      ''');

      // PreÃ§os por produto Ã— tabela (TABELA_PRECOS_ITENS via MOB_TABELAPRECO)
      await txn.execute('''
        CREATE TABLE product_prices (
          product_code    TEXT NOT NULL,
          price_table_id  TEXT NOT NULL,
          price           REAL NOT NULL,
          last_synced_at  TEXT,
          PRIMARY KEY (product_code, price_table_id)
        )
      ''');
      await txn.execute('CREATE INDEX IF NOT EXISTS idx_pp_table ON product_prices (price_table_id)');

      // â”€â”€ v23: ConfiguraÃ§Ãµes comportamentais da empresa â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
      // Inclui priceTableMode (v23) e allowNegativeStock (v28)
      await txn.execute('''
        CREATE TABLE IF NOT EXISTS company_settings (
          id                   INTEGER PRIMARY KEY,
          price_table_mode     TEXT    NOT NULL DEFAULT 'none',
          allow_negative_stock INTEGER NOT NULL DEFAULT 0,
          synced_at            TEXT
        )
      ''');
    });
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // Migrations â€” adicionar quando _dbVersion for incrementado
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 34) {
      try {
        await db.execute("ALTER TABLE orders ADD COLUMN company_id TEXT NOT NULL DEFAULT '1'");
      } catch (_) {}
    }

    if (oldVersion < 35) {
      try {
        await db.execute("ALTER TABLE seller_kpis ADD COLUMN company_id TEXT NOT NULL DEFAULT '1'");
        await db.execute("ALTER TABLE erp_sales_rankings ADD COLUMN company_id TEXT NOT NULL DEFAULT '1'");
      } catch (_) {}
    }

    if (oldVersion < 36) {
      try {
        await db.execute("ALTER TABLE seller_kpis ADD COLUMN company_id TEXT NOT NULL DEFAULT '1'");
        await db.execute("ALTER TABLE erp_sales_rankings ADD COLUMN company_id TEXT NOT NULL DEFAULT '1'");
      } catch (_) {}
    }

    if (oldVersion < 2) {
      await db.transaction((txn) async {
        await txn.insert('sync_metadata', {
          'key':   'last_customers_sync',
          'value': DateTime.fromMillisecondsSinceEpoch(0).toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        await txn.execute('''
          CREATE TABLE IF NOT EXISTS seller_sessions (
            id TEXT PRIMARY KEY, seller_id TEXT NOT NULL,
            seller_name TEXT NOT NULL, company_id TEXT NOT NULL,
            company_name TEXT NOT NULL, pin_hash TEXT NOT NULL,
            created_at TEXT NOT NULL, active INTEGER NOT NULL DEFAULT 1
          )
        ''');
        await txn.execute('CREATE INDEX IF NOT EXISTS idx_sessions_active ON seller_sessions (active)');
        await txn.execute('''
          CREATE TABLE IF NOT EXISTS customers (
            id TEXT PRIMARY KEY, name TEXT NOT NULL,
            cnpj TEXT, city TEXT, state TEXT,
            credit_limit REAL NOT NULL DEFAULT 0, last_synced_at TEXT
          )
        ''');
        await txn.execute('CREATE INDEX IF NOT EXISTS idx_customers_name ON customers (name)');
      });
    }
    if (oldVersion < 3) {
      await db.transaction((txn) async {
        // Expande tabela products com campos reais do PIVETA.FDB
        await txn.execute('ALTER TABLE products ADD COLUMN name_short   TEXT');
        await txn.execute('ALTER TABLE products ADD COLUMN price_min    REAL');
        await txn.execute('ALTER TABLE products ADD COLUMN brand        TEXT');
        await txn.execute('ALTER TABLE products ADD COLUMN bar_code     TEXT');
        await txn.execute('ALTER TABLE products ADD COLUMN reference    TEXT');
        await txn.execute('ALTER TABLE products ADD COLUMN max_discount REAL');
        // Cache de vendedores
        await txn.execute('''
          CREATE TABLE IF NOT EXISTS sellers (
            id TEXT PRIMARY KEY, mobile_id TEXT,
            name TEXT NOT NULL, email TEXT, pin TEXT,
            max_discount REAL, commission REAL, last_synced_at TEXT
          )
        ''');
        await txn.insert('sync_metadata', {
          'key':   'last_sellers_sync',
          'value': DateTime.fromMillisecondsSinceEpoch(0).toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      });
    }
    if (oldVersion < 4) {
      await db.transaction((txn) async {
        // Formas de pagamento
        await txn.execute('''
          CREATE TABLE IF NOT EXISTS payment_species (
            payment_species_id TEXT PRIMARY KEY,
            name               TEXT NOT NULL,
            type               TEXT,
            days               INTEGER,
            last_synced_at     TEXT
          )
        ''');
        // Naturezas de operaÃ§Ã£o
        await txn.execute('''
          CREATE TABLE IF NOT EXISTS natureza_operacao (
            natureza_id    TEXT PRIMARY KEY,
            descricao      TEXT NOT NULL,
            descricao_nota TEXT,
            codigo_fiscal  TEXT,
            es             TEXT,
            mob_ordem      INTEGER,
            last_synced_at TEXT
          )
        ''');
        // Campos de pagamento/desconto nos pedidos
        await txn.execute('ALTER TABLE orders ADD COLUMN payment_species_id   TEXT');
        await txn.execute('ALTER TABLE orders ADD COLUMN payment_species_name TEXT');
        await txn.execute('ALTER TABLE orders ADD COLUMN payment_days         INTEGER');
        await txn.execute('ALTER TABLE orders ADD COLUMN discount_percent     REAL NOT NULL DEFAULT 0');
        await txn.execute('ALTER TABLE orders ADD COLUMN discount_value       REAL NOT NULL DEFAULT 0');
        await txn.execute('ALTER TABLE orders ADD COLUMN natureza_id          TEXT');
        await txn.execute('ALTER TABLE orders ADD COLUMN natureza_descricao   TEXT');
        // Desconto por item
        await txn.execute('ALTER TABLE order_items ADD COLUMN discount REAL NOT NULL DEFAULT 0');
      });
    }

    if (oldVersion < 5) {
      await db.transaction((txn) async {
        // Mensagem de erro da VPS + ID do pedido no ERP Firebird
        await txn.execute('ALTER TABLE orders ADD COLUMN error_message TEXT');
        await txn.execute('ALTER TABLE orders ADD COLUMN erp_order_id  TEXT');
        // Categoria e preÃ§o de custo do produto
        await txn.execute('ALTER TABLE products ADD COLUMN category   TEXT');
        await txn.execute('ALTER TABLE products ADD COLUMN price_cost REAL');
        // TÃ­tulos financeiros do cliente (MOB_LISTACONTAS)
        await txn.execute('''
          CREATE TABLE IF NOT EXISTS financials (
            id                  TEXT PRIMARY KEY,
            customer_id         TEXT NOT NULL,
            doc_number          TEXT,
            amount              REAL NOT NULL DEFAULT 0,
            interest            REAL NOT NULL DEFAULT 0,
            due_date            TEXT,
            payment_species_id  TEXT,
            is_paid             INTEGER NOT NULL DEFAULT 0,
            type                TEXT,
            payment_date        TEXT,
            last_synced_at      TEXT
          )
        ''');
        await txn.execute('CREATE INDEX IF NOT EXISTS idx_fin_customer ON financials (customer_id)');
        await txn.execute('CREATE INDEX IF NOT EXISTS idx_fin_paid ON financials (is_paid)');
      });
    }

    if (oldVersion < 6) {
      await db.transaction((txn) async {
        // discount_mode: 'percent' ou 'value' â€” modo escolhido pelo vendedor
        // raw_discount_input: valor bruto digidado (antes de converter para %)
        // NecessÃ¡rio para restaurar a UI do cart_screen corretamente apÃ³s relay
        await txn.execute(
          "ALTER TABLE order_items ADD COLUMN discount_mode TEXT NOT NULL DEFAULT 'percent'",
        );
        await txn.execute(
          'ALTER TABLE order_items ADD COLUMN raw_discount_input REAL NOT NULL DEFAULT 0',
        );
      });
    }

    if (oldVersion < 7) {
      await db.execute('ALTER TABLE seller_sessions ADD COLUMN max_discount REAL');
    }

    if (oldVersion < 8) {
      // Campos de contato e endereÃ§o completo do cliente
      await db.execute('ALTER TABLE customers ADD COLUMN phone         TEXT');
      await db.execute('ALTER TABLE customers ADD COLUMN email         TEXT');
      await db.execute('ALTER TABLE customers ADD COLUMN street        TEXT');
      await db.execute('ALTER TABLE customers ADD COLUMN street_number TEXT');
      await db.execute('ALTER TABLE customers ADD COLUMN neighborhood  TEXT');
      await db.execute('ALTER TABLE customers ADD COLUMN zip_code      TEXT');
    }

    if (oldVersion < 9) {
      // JWT Coliseu Identity
      try {
        await db.execute('ALTER TABLE seller_sessions ADD COLUMN access_token TEXT');
        await db.execute('ALTER TABLE seller_sessions ADD COLUMN refresh_token TEXT');
      } catch (_) {}
    }

    if (oldVersion < 10) {
      // Fix para bases recÃ©m-criadas na v9 que pularam o _onCreate incompleto
      try {
        await db.execute('ALTER TABLE seller_sessions ADD COLUMN access_token TEXT');
        await db.execute('ALTER TABLE seller_sessions ADD COLUMN refresh_token TEXT');
      } catch (_) {}
    }

    if (oldVersion < 11) {
      // Fix para bases recÃ©m-criadas na v9/v10 que pularam os campos de endereÃ§o na tabela de clientes
      try {
        await db.execute('ALTER TABLE customers ADD COLUMN phone         TEXT');
        await db.execute('ALTER TABLE customers ADD COLUMN email         TEXT');
        await db.execute('ALTER TABLE customers ADD COLUMN street        TEXT');
        await db.execute('ALTER TABLE customers ADD COLUMN street_number TEXT');
        await db.execute('ALTER TABLE customers ADD COLUMN neighborhood  TEXT');
        await db.execute('ALTER TABLE customers ADD COLUMN zip_code      TEXT');
      } catch (_) {}
    }

    if (oldVersion < 12) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS payment_conditions (
          id             TEXT PRIMARY KEY,
          descricao      TEXT NOT NULL,
          desconto_max   REAL,
          parcelas       INTEGER,
          dias_entrada   INTEGER,
          dias_parcelas  INTEGER,
          mob_ordem      INTEGER
        )
      ''');
      
      try {
        await db.execute('ALTER TABLE orders ADD COLUMN payment_condition_id TEXT');
        await db.execute('ALTER TABLE orders ADD COLUMN payment_condition_name TEXT');
      } catch (_) {}
    }

    if (oldVersion < 13) {
      // ForÃ§a a criaÃ§Ã£o das tabelas caso o device jÃ¡ estivesse na v12 antes delas serem adicionadas ao cÃ³digo
      await db.execute('''
        CREATE TABLE IF NOT EXISTS payment_conditions (
          id             TEXT PRIMARY KEY,
          descricao      TEXT NOT NULL,
          desconto_max   REAL,
          parcelas       INTEGER,
          dias_entrada   INTEGER,
          dias_parcelas  INTEGER,
          mob_ordem      INTEGER
        )
      ''');
      
      await db.execute('''
        CREATE TABLE IF NOT EXISTS natureza_operacao (
          natureza_id    TEXT  PRIMARY KEY,
          descricao      TEXT  NOT NULL,
          descricao_nota TEXT,
          codigo_fiscal  TEXT,
          es             TEXT,
          mob_ordem      INTEGER,
          last_synced_at TEXT
        )
      ''');
    }

    if (oldVersion < 14) {
      // Vincula condiÃ§Ã£o â†” espÃ©cie (ID_FORMA_PAGAMENTO de MOB_TABELAFORMASPAGTO)
      try {
        await db.execute('ALTER TABLE payment_conditions ADD COLUMN especie_id TEXT');
      } catch (_) {} // jÃ¡ existe em bases criadas do zero com _dbVersion >= 14
    }

    if (oldVersion < 15) {
      // Limpa linhas corrompidas da sync antiga (bug: UPPERCASE nÃ£o mapeado)
      try {
        await db.execute("DELETE FROM payment_conditions WHERE id IS NULL OR id = ''");
        await db.execute("DELETE FROM natureza_operacao WHERE natureza_id IS NULL OR natureza_id = ''");
      } catch (_) {}
    }

    if (oldVersion < 16) {
      // Fix 1 â€” Vendedor responsÃ¡vel pelo cliente (enviado pelo Worker no payload)
      // NecessÃ¡rio para filtrar clientes por vendedor logado offline.
      try {
        await db.execute('ALTER TABLE customers ADD COLUMN seller_id TEXT');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_customers_seller ON customers (seller_id)');
      } catch (_) {} // seguro: tenta mas nÃ£o quebra se jÃ¡ existir
    }

    if (oldVersion < 17) {
      // â”€â”€ v17: Ãndices para busca rÃ¡pida e analytics â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
      // Produtos â€” busca por campo (brand, reference, bar_code)
      await db.execute('CREATE INDEX IF NOT EXISTS idx_products_brand     ON products (brand)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_products_reference ON products (reference)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_products_barcode   ON products (bar_code)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_products_code      ON products (code)');

      // Pedidos â€” analytics por cliente e perÃ­odo
      await db.execute('CREATE INDEX IF NOT EXISTS idx_orders_customer    ON orders (customer_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_orders_sync_date   ON orders (sync_status, created_at DESC)');

      // Itens de pedido â€” ranking de produtos mais vendidos
      await db.execute('CREATE INDEX IF NOT EXISTS idx_oi_product         ON order_items (product_code)');
    }

    if (oldVersion < 18) {
      // â”€â”€ v18: Produtos favoritos â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
      await db.execute('''
        CREATE TABLE IF NOT EXISTS product_favorites (
          code     TEXT PRIMARY KEY,
          added_at TEXT NOT NULL DEFAULT (datetime('now'))
        )
      ''');
    }

    if (oldVersion < 19) {
      // â”€â”€ v19: KPIs de desempenho reais do ERP (MINHASVENDAS) â”€â”€â”€â”€â”€â”€â”€â”€â”€
      await db.execute('''
        CREATE TABLE IF NOT EXISTS seller_kpis (
          id                   INTEGER PRIMARY KEY AUTOINCREMENT,
          company_id           TEXT    NOT NULL DEFAULT '1',
          seller_id            TEXT    NOT NULL,
          month                INTEGER NOT NULL,
          year                 INTEGER NOT NULL,
          venda_diaria         REAL    NOT NULL DEFAULT 0,
          venda_mensal         REAL    NOT NULL DEFAULT 0,
          comissao_diaria      REAL    NOT NULL DEFAULT 0,
          comissao_mensal       REAL    NOT NULL DEFAULT 0,
          meta_diaria          REAL    NOT NULL DEFAULT 0,
          meta_mensal          REAL    NOT NULL DEFAULT 0,
          servico_mensal       REAL    NOT NULL DEFAULT 0,
          comissao_sv_mensal   REAL    NOT NULL DEFAULT 0,
          total_diario         REAL    NOT NULL DEFAULT 0,
          total_mensal         REAL    NOT NULL DEFAULT 0,
          comissao_diaria_r    REAL    NOT NULL DEFAULT 0,
          comissao_mensal_r    REAL    NOT NULL DEFAULT 0,
          synced_at            TEXT    NOT NULL
        )
      ''');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_skpis_seller ON seller_kpis (company_id, seller_id, year, month)');
    }

    if (oldVersion < 20) {
      // â”€â”€ v20: Rankings de vendas reais do ERP (L_VENDAS_*) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
      await db.execute('''
        CREATE TABLE IF NOT EXISTS erp_sales_rankings (
          id                   INTEGER PRIMARY KEY AUTOINCREMENT,
          company_id           TEXT    NOT NULL DEFAULT '1',
          seller_id            TEXT    NOT NULL,
          month                INTEGER NOT NULL,
          year                 INTEGER NOT NULL,
          top_products_json    TEXT    NOT NULL DEFAULT '[]',
          top_clients_json     TEXT    NOT NULL DEFAULT '[]',
          by_region_json       TEXT    NOT NULL DEFAULT '[]',
          synced_at            TEXT    NOT NULL
        )
      ''');
      await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_rankings_seller ON erp_sales_rankings (seller_id, year, month)');
    }

    if (oldVersion < 21) {
      // â”€â”€ v21: Dados de parcelamento salvos no pedido (FORMA_PGTO) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
      // NecessÃ¡rios para gerar PEDIDOS_DOCS corretos sem tocar na SP Firebird.
      try {
        await db.execute('ALTER TABLE orders ADD COLUMN payment_installments        INTEGER');
        await db.execute('ALTER TABLE orders ADD COLUMN payment_days_per_installment INTEGER');
        await db.execute('ALTER TABLE orders ADD COLUMN payment_entry_days           INTEGER');
      } catch (_) {} // seguro: coluna pode jÃ¡ existir em bancos criados do zero
    }

    if (oldVersion < 22) {
      // â”€â”€ v22: Suporte a Tabela de PreÃ§o (TABELA_PRECOS) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
      // CabeÃ§alhos das tabelas de preÃ§o
      await db.execute('''
        CREATE TABLE IF NOT EXISTS price_tables (
          id          TEXT PRIMARY KEY,
          name        TEXT NOT NULL,
          markup_pct  REAL NOT NULL DEFAULT 0
        )
      ''');

      // PreÃ§os produto Ã— tabela (via MOB_TABELAPRECO do Firebird)
      await db.execute('''
        CREATE TABLE IF NOT EXISTS product_prices (
          product_code    TEXT NOT NULL,
          price_table_id  TEXT NOT NULL,
          price           REAL NOT NULL,
          PRIMARY KEY (product_code, price_table_id)
        )
      ''');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_pp_table ON product_prices (price_table_id)');

      // Vincula cliente Ã  sua tabela de preÃ§o (CLIENTES.ID_TABELA)
      try {
        await db.execute('ALTER TABLE customers ADD COLUMN price_table_id TEXT');
      } catch (_) {} // seguro: pode jÃ¡ existir em bases criadas do zero com v22
    }

    if (oldVersion < 23) {
      // â”€â”€ v23: ConfiguraÃ§Ãµes comportamentais da empresa (priceTableMode) â”€â”€â”€â”€
      // Armazenadas localmente por sincronizaÃ§Ã£o do endpoint /api/sync/company-settings
      await db.execute('''
        CREATE TABLE IF NOT EXISTS company_settings (
          id               INTEGER PRIMARY KEY,
          price_table_mode TEXT    NOT NULL DEFAULT 'none',
          synced_at        TEXT
        )
      ''');
    }

    if (oldVersion < 24) {
      // â”€â”€ v24: Corrige bancos criados via _onCreate antigo (sem as colunas v21). â”€â”€
      // O _onCreate da versÃ£o â‰¤ 23 nÃ£o incluÃ­a payment_installments,
      // payment_days_per_installment e payment_entry_days na tabela orders,
      // mesmo que o cÃ³digo de saveDraft jÃ¡ tentasse inserir esses campos
      // quando dbVersion >= 21. Isso causava SQLITE_ERROR em instalaÃ§Ãµes limpas.
      try {
        await db.execute('ALTER TABLE orders ADD COLUMN payment_installments         INTEGER');
      } catch (_) {} // seguro: coluna pode jÃ¡ existir em bancos migrados corretamente
      try {
        await db.execute('ALTER TABLE orders ADD COLUMN payment_days_per_installment INTEGER');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE orders ADD COLUMN payment_entry_days           INTEGER');
      } catch (_) {}
    }
    if (oldVersion < 25) {
      // â”€â”€ v25: Coluna by_seller_json para rankings de vendas por vendedor â”€â”€â”€â”€â”€â”€â”€â”€
      // Referenciada em SalesRankings.fromMap() mas ausente no schema da v20.
      // Inserida com default '[]' para compatibilidade com bancos existentes.
      try {
        await db.execute(
            "ALTER TABLE erp_sales_rankings ADD COLUMN by_seller_json TEXT NOT NULL DEFAULT '[]'");
      } catch (_) {} // seguro: coluna pode jÃ¡ existir em bancos criados do zero
    }
    
    if (oldVersion < 26) {
      // â”€â”€ v26: GrÃ¡ficos de Faturamento reais do ERP â”€â”€â”€â”€â”€â”€â”€â”€
      try {
        await db.execute("ALTER TABLE erp_sales_rankings ADD COLUMN revenue_by_day_json  TEXT NOT NULL DEFAULT '[]'");
        await db.execute("ALTER TABLE erp_sales_rankings ADD COLUMN client_health_json   TEXT NOT NULL DEFAULT '{}'");
        await db.execute("ALTER TABLE erp_sales_rankings ADD COLUMN category_mix_json    TEXT NOT NULL DEFAULT '[]'");
        await db.execute("ALTER TABLE erp_sales_rankings ADD COLUMN heatmap_stats_json   TEXT NOT NULL DEFAULT '[]'");
      } catch (_) {}
    }

    if (oldVersion < 27) {
      // â”€â”€ v27: Safety-net â€” cria erp_sales_rankings caso nÃ£o exista â”€â”€â”€â”€â”€â”€
      // Dispositivos que estavam na v20+ quando a migration v20 foi deployada
      // nunca executaram o "if (oldVersion < 20)" e ficaram sem a tabela.
      await db.execute('''
        CREATE TABLE IF NOT EXISTS erp_sales_rankings (
          id                   INTEGER PRIMARY KEY AUTOINCREMENT,
          company_id           TEXT    NOT NULL DEFAULT '1',
          seller_id            TEXT    NOT NULL,
          month                INTEGER NOT NULL,
          year                 INTEGER NOT NULL,
          top_products_json    TEXT    NOT NULL DEFAULT '[]',
          top_clients_json     TEXT    NOT NULL DEFAULT '[]',
          by_region_json       TEXT    NOT NULL DEFAULT '[]',
          by_seller_json       TEXT    NOT NULL DEFAULT '[]',
          revenue_by_day_json  TEXT    NOT NULL DEFAULT '[]',
          client_health_json   TEXT    NOT NULL DEFAULT '{}',
          category_mix_json    TEXT    NOT NULL DEFAULT '[]',
          heatmap_stats_json   TEXT    NOT NULL DEFAULT '[]',
          synced_at            TEXT    NOT NULL
        )
      ''');
      await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_rankings_seller ON erp_sales_rankings (seller_id, year, month)');
    }

    if (oldVersion < 28) {
      // â”€â”€ v28: Coluna period para filtro por perÃ­odo (today/week/month/all) â”€â”€
      try {
        await db.execute(
            "ALTER TABLE erp_sales_rankings ADD COLUMN period TEXT NOT NULL DEFAULT 'month'");
      } catch (_) {} // seguro: coluna pode jÃ¡ existir
      // Recria index para incluir period
      await db.execute('DROP INDEX IF EXISTS idx_rankings_seller');
      await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_rankings_seller ON erp_sales_rankings (company_id, seller_id, year, month, period)');
    }

    if (oldVersion < 29) {
      // â”€â”€ v29: Colunas de desconto para round-trip (persist/restore) â”€â”€â”€â”€
      // order_items: modo e input bruto do desconto por item
      try {
        await db.execute(
            "ALTER TABLE order_items ADD COLUMN discount_mode TEXT NOT NULL DEFAULT 'percent'");
      } catch (_) {}
      try {
        await db.execute(
            'ALTER TABLE order_items ADD COLUMN raw_discount_input REAL NOT NULL DEFAULT 0');
      } catch (_) {}
      // orders: desconto global do pedido
      try {
        await db.execute(
            'ALTER TABLE orders ADD COLUMN order_discount_input REAL NOT NULL DEFAULT 0');
      } catch (_) {}
      try {
        await db.execute(
            "ALTER TABLE orders ADD COLUMN order_discount_mode TEXT NOT NULL DEFAULT 'percent'");
      } catch (_) {}
    }

    if (oldVersion < 30) {
      // â”€â”€ v30: Safety-net â€” dispositivos jÃ¡ na v29 sem as colunas de desconto â”€â”€
      // Ocorre quando o app foi atualizado em produÃ§Ã£o sem incrementar _dbVersion.
      // O try/catch garante que nÃ£o quebra bancos que jÃ¡ tÃªm as colunas.
      try {
        await db.execute(
            'ALTER TABLE orders ADD COLUMN order_discount_input REAL NOT NULL DEFAULT 0');
      } catch (_) {}
      try {
        await db.execute(
            "ALTER TABLE orders ADD COLUMN order_discount_mode TEXT NOT NULL DEFAULT 'percent'");
      } catch (_) {}
    }

    if (oldVersion < 31) {
      // â”€â”€ v31: allow_negative_stock na tabela company_settings â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
      // Permite configurar por empresa se a venda sem estoque Ã© permitida.
      // O _onCreate jÃ¡ inclui a coluna â€” esta migration Ã© para dispositivos
      // que jÃ¡ tinham a tabela sem a nova coluna.
      try {
        await db.execute(
          'ALTER TABLE company_settings ADD COLUMN allow_negative_stock INTEGER NOT NULL DEFAULT 0',
        );
      } catch (_) {} // seguro: coluna pode jÃ¡ existir em bancos criados do zero
    }

    if (oldVersion < 32) {
      // â”€â”€ v32: Safety-net para instalaÃ§Ãµes limpas na v31 â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
      // A versÃ£o v31 introduzia um bug onde o _onCreate para instalaÃ§Ãµes limpas
      // nÃ£o criava as colunas order_discount_input e order_discount_mode.
      // E devices atualizados da v28 direto para a v31 ficavam sem elas.
      try {
        await db.execute(
            'ALTER TABLE orders ADD COLUMN order_discount_input REAL NOT NULL DEFAULT 0');
      } catch (_) {}
      try {
        await db.execute(
            "ALTER TABLE orders ADD COLUMN order_discount_mode TEXT NOT NULL DEFAULT 'percent'");
      } catch (_) {}
    }
    if (oldVersion < 33) {
      // â”€â”€ v33: Metadados de filial no catÃ¡logo de produtos (FASE 4 Multi-tenant) â”€â”€
      // erp_depto_padrao: ID do departamento ERP da filial padrÃ£o da empresa.
      // Populado pelo Worker (SyncCatalogJob) com base nas filiais configuradas.
      // Usado pelo app para exibir badge de estoque por filial no catÃ¡logo.
      try {
        await db.execute(
          'ALTER TABLE products ADD COLUMN erp_depto_padrao INTEGER',
        );
      } catch (_) {} // seguro: coluna pode jÃ¡ existir em instalaÃ§Ãµes limpas
    }
    if (oldVersion < 37) {
      try {
        await db.execute(
          'ALTER TABLE product_prices ADD COLUMN last_synced_at TEXT',
        );
      } catch (_) {}
    }
    if (oldVersion < 38) {
      try {
        await db.execute(
          'ALTER TABLE sellers ADD COLUMN erp_empresa_id INTEGER',
        );
      } catch (_) {}
    }
  } // fim _onUpgrade


  // CRUD base â€” sync_queue
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Insere um item na fila de sync.
  Future<void> enqueueSyncItem(Map<String, dynamic> item) async {
    final db = await database;
    await db.insert('sync_queue', item, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Retorna todos os itens com [syncStatus] na fila.
  Future<List<Map<String, dynamic>>> getSyncQueue(String syncStatus) async {
    final db = await database;
    return db.query(
      'sync_queue',
      where: 'sync_status = ?',
      whereArgs: [syncStatus],
      orderBy: 'created_at ASC',
    );
  }

  /// Atualiza o status de um item da fila de sync.
  Future<void> updateSyncStatus(
    String id,
    String status, {
    String? errorMessage,
  }) async {
    final db     = await database;
    final values = <String, dynamic>{'sync_status': status};
    if (errorMessage != null) values['error_message'] = errorMessage;

    await db.update(
      'sync_queue',
      values,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Incrementa o contador de retry de um item.
  Future<void> incrementRetryCount(String id) async {
    final db = await database;
    await db.rawUpdate(
      'UPDATE sync_queue SET retry_count = retry_count + 1 WHERE id = ?',
      [id],
    );
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // CRUD base â€” orders
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Insere ou atualiza um pedido.
  Future<void> upsertOrder(Map<String, dynamic> order) async {
    final db = await database;
    await db.insert('orders', order, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Retorna todos os pedidos ordenados por data de criaÃ§Ã£o decrescente, filtrados por empresa.
  Future<List<Map<String, dynamic>>> getAllOrders(String companyId) async {
    final db = await database;
    return db.query('orders', where: 'company_id = ?', whereArgs: [companyId], orderBy: 'created_at DESC');
  }

  /// Atualiza o sync_status de um pedido.
  Future<void> updateOrderSyncStatus(
    String id,
    String status, {
    String? serverConfirmedAt,
    String? erpOrderId,
    String? errorMessage,
  }) async {
    final db     = await database;
    final values = <String, dynamic>{
      'sync_status': status,
      'updated_at':  DateTime.now().toIso8601String(),
    };
    if (serverConfirmedAt != null) values['server_confirmed_at'] = serverConfirmedAt;
    if (erpOrderId    != null)     values['erp_order_id']        = erpOrderId;
    if (errorMessage  != null)     values['error_message']       = errorMessage;
    await db.update('orders', values, where: 'id = ?', whereArgs: [id]);
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // CRUD base â€” products (cache do catÃ¡logo)
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Insere ou atualiza um produto (upsert por code).
  Future<void> upsertProduct(Map<String, dynamic> product) async {
    final db = await database;
    await db.insert('products', product, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Upsert em batch â€” mais eficiente que chamar [upsertProduct] em loop.
  Future<void> upsertProductsBatch(List<Map<String, dynamic>> products) async {
    final db = await database;
    final batch = db.batch();
    for (final p in products) {
      batch.insert('products', p, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  /// Busca produtos por nome ou cÃ³digo.
  Future<List<Map<String, dynamic>>> searchProducts(String query) async {
    final db    = await database;
    final term  = '%${query.toLowerCase()}%';
    return db.query(
      'products',
      where: 'LOWER(name) LIKE ? OR LOWER(code) LIKE ?',
      whereArgs: [term, term],
      orderBy: 'name ASC',
      limit: 100,
    );
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // Metadados de sync
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Retorna o valor de uma chave de metadados.
  Future<String?> getSyncMetadata(String key) async {
    final db   = await database;
    final rows = await db.query(
      'sync_metadata',
      where: 'key = ?',
      whereArgs: [key],
    );
    return rows.isNotEmpty ? rows.first['value'] as String : null;
  }

  /// Atualiza ou insere um metadado de sync.
  Future<void> setSyncMetadata(String key, String value) async {
    final db = await database;
    await db.insert(
      'sync_metadata',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // CRUD base â€” payment_species
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Upsert em batch de formas de pagamento â€” chamado pelo SyncService.
  Future<void> upsertPaymentSpeciesBatch(List<Map<String, dynamic>> species) async {
    final db    = await database;
    final batch = db.batch();
    for (final s in species) {
      batch.insert('payment_species', s, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  /// Upsert em batch de condiÃ§Ãµes de pagamento â€” chamado pelo SyncService.
  Future<void> upsertPaymentConditionsBatch(List<Map<String, dynamic>> conditions) async {
    final db    = await database;
    final batch = db.batch();
    for (final c in conditions) {
      batch.insert('payment_conditions', c, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  /// Upsert em batch de naturezas de operaÃ§Ã£o â€” chamado pelo SyncService.
  Future<void> upsertNaturezaBatch(List<Map<String, dynamic>> naturezas) async {
    final db    = await database;
    final batch = db.batch();
    for (final n in naturezas) {
      batch.insert('natureza_operacao', n, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  /// Salva KPIs de desempenho reais do ERP (MINHASVENDAS).
  ///
  /// Faz upsert por seller_id + month + year:
  /// deleta registro anterior e insere o novo.
  Future<void> upsertSellerKpis(Map<String, dynamic> kpis) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('seller_kpis',
          where: 'company_id = ? AND seller_id = ? AND month = ? AND year = ?',
          whereArgs: [kpis['company_id'], kpis['seller_id'], kpis['month'], kpis['year']]);
      await txn.insert('seller_kpis', kpis);
    });
  }

  /// Retorna os KPIs mais recentes de um vendedor para o mÃªs/ano.
  Future<Map<String, dynamic>?> getSellerKpis(
      String companyId, String sellerId, int month, int year) async {
    final db = await database;
    final rows = await db.query('seller_kpis',
        where: 'company_id = ? AND seller_id = ? AND month = ? AND year = ?',
        whereArgs: [companyId, sellerId, month, year],
        limit: 1);
    return rows.isNotEmpty ? rows.first : null;
  }

  /// Salva rankings de vendas do ERP (L_VENDAS_*).
  ///
  /// Faz upsert por seller_id + month + year + period:
  /// deleta registro anterior e insere o novo.
  Future<void> upsertSalesRankings(Map<String, dynamic> data) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('erp_sales_rankings',
          where: 'company_id = ? AND seller_id = ? AND month = ? AND year = ? AND period = ?',
          whereArgs: [data['company_id'], data['seller_id'], data['month'], data['year'], data['period'] ?? 'month']);
      await txn.insert('erp_sales_rankings', data);
    });
  }

  /// Retorna os rankings de vendas de um vendedor para um perÃ­odo especÃ­fico.
  Future<Map<String, dynamic>?> getSalesRankings(
      String companyId, String sellerId, int month, int year, {String period = 'month'}) async {
    final db = await database;
    final rows = await db.query('erp_sales_rankings',
        where: 'company_id = ? AND seller_id = ? AND month = ? AND year = ? AND period = ?',
        whereArgs: [companyId, sellerId, month, year, period],
        limit: 1);
    return rows.isNotEmpty ? rows.first : null;
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  /// Fecha o banco de dados. Usar apenas em testes.
  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}

class _MockBatch implements Batch {
  @override
  void delete(String table, {String? where, List<Object?>? whereArgs}) {}
  @override
  void execute(String sql, [List<Object?>? arguments]) {}
  @override
  void insert(String table, Map<String, Object?> values, {String? nullColumnHack, ConflictAlgorithm? conflictAlgorithm}) {}
  @override
  void query(String table, {bool? distinct, List<String>? columns, String? where, List<Object?>? whereArgs, String? groupBy, String? having, String? orderBy, int? limit, int? offset}) {}
  @override
  void rawDelete(String sql, [List<Object?>? arguments]) {}
  @override
  void rawInsert(String sql, [List<Object?>? arguments]) {}
  @override
  void rawQuery(String sql, [List<Object?>? arguments]) {}
  @override
  void rawUpdate(String sql, [List<Object?>? arguments]) {}
  @override
  void update(String table, Map<String, Object?> values, {String? where, List<Object?>? whereArgs, ConflictAlgorithm? conflictAlgorithm}) {}
  @override
  Future<List<Object?>> commit({bool? exclusive, bool? noResult, bool? continueOnError}) => Future.value([]);
  @override
  int get length => 0;

  @override
  Future<List<Object?>> apply({bool? noResult, bool? continueOnError}) => Future.value([]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}




/// Testes unitários do CartNotifier.
///
/// Estratégia: usa SQLite in-memory (sqflite_ffi) para o OrderRepository
/// e um FakePriceService para preços, sem tocar no Firebird ou HTTP.
///
/// O `_autoSave()` do CartNotifier guard `if (_customerId.isEmpty) return;`
/// garante que a maioria dos testes não dispara I/O de banco. Apenas os testes
/// de `setCustomer()` criam o banco in-memory real.
///
/// Cobertura (23 testes):
///   Estado inicial, addProduct (6), removeItem (3),
///   updateDiscount (3), setOrderDiscount (5), setPaymentSpecies (1),
///   setNatureza (2), tabela de preço (2), AllowNegativeStock (3)

library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:coliseu_speed/core/cart/cart_notifier.dart';
import 'package:coliseu_speed/core/database/database_helper.dart';
import 'package:coliseu_speed/core/network/connectivity_service.dart';
import 'package:coliseu_speed/core/repositories/models/models.dart';
import 'package:coliseu_speed/core/repositories/order_repository.dart';
import 'package:coliseu_speed/core/repositories/product_repository.dart';
import 'package:coliseu_speed/core/repositories/customer_repository.dart';
import 'package:coliseu_speed/core/services/company_settings_service.dart';
import 'package:coliseu_speed/core/services/discount_service.dart';
import 'package:coliseu_speed/core/services/price_service.dart';
import 'package:coliseu_speed/core/sync/sync_service.dart';
import 'package:coliseu_speed/core/config/app_config_service.dart';
import 'package:coliseu_speed/core/session/session_service.dart';
import 'package:coliseu_speed/core/session/session_model.dart';
import 'package:get_it/get_it.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FakePriceService — sem SQLite, retorna preços configurados
// ─────────────────────────────────────────────────────────────────────────────

class _FakePriceService extends PriceService {
  final Map<String, double> _overrides;

  // Chama super() sem db — PriceService usa DatabaseHelper() como default.
  // Nunca será acessado pois sobrescrevemos todos os métodos.
  _FakePriceService([this._overrides = const {}]) : super();

  @override
  Future<double> resolvePrice({
    required double basePrice,
    required String productCode,
    String? priceTableId,
  }) async {
    if (priceTableId == null || priceTableId.isEmpty) return basePrice;
    return _overrides[productCode] ?? basePrice;
  }

  @override
  Future<Map<String, double>> resolvePrices({
    required List<Product> products,
    String? priceTableId,
  }) async =>
      {for (final p in products) p.code: _overrides[p.code] ?? p.price};

  @override
  Future<String?> getActiveTableName(String? tableId) async => null;
}

// ─────────────────────────────────────────────────────────────────────────────
// Setup de banco in-memory mínimo para o OrderRepository
// ─────────────────────────────────────────────────────────────────────────────

Future<Database> _openTestDb() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  return databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE orders (
            id                           TEXT    PRIMARY KEY,
            company_id                   TEXT    NOT NULL DEFAULT '1',
            customer_id                  TEXT    NOT NULL,
            customer_name                TEXT    NOT NULL,
            total_amount                 REAL    NOT NULL DEFAULT 0,
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
        await db.execute('''
          CREATE TABLE order_items (
            id TEXT PRIMARY KEY,
            order_id TEXT NOT NULL,
            product_code TEXT NOT NULL,
            product_name TEXT NOT NULL,
            quantity REAL NOT NULL,
            unit_price REAL NOT NULL,
            discount REAL DEFAULT 0,
            total_price REAL NOT NULL,
            discount_mode TEXT DEFAULT 'percent',
            raw_discount_input REAL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE sync_queue (
            id TEXT PRIMARY KEY,
            entity_type TEXT,
            entity_id TEXT,
            payload TEXT,
            sync_status TEXT,
            created_at TEXT,
            updated_at TEXT,
            retry_count INTEGER DEFAULT 0,
            error_message TEXT
          )
        ''');
        // Tabela necessária para DatabaseHelper.getAllOrders()
        await db.execute('''
          CREATE TABLE IF NOT EXISTS price_tables (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS product_prices (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            product_code TEXT NOT NULL,
            price_table_id TEXT NOT NULL,
            price REAL NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS customers (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            cnpj TEXT,
            city TEXT,
            state TEXT,
            credit_limit REAL NOT NULL DEFAULT 0,
            last_synced_at TEXT,
            phone TEXT,
            email TEXT,
            street TEXT,
            street_number TEXT,
            neighborhood TEXT,
            zip_code TEXT,
            seller_id TEXT,
            price_table_id TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS products (
            code TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            name_short TEXT,
            price REAL NOT NULL DEFAULT 0,
            price_min REAL,
            stock REAL NOT NULL DEFAULT 0,
            unit TEXT,
            brand TEXT,
            bar_code TEXT,
            reference TEXT,
            max_discount REAL,
            category TEXT,
            price_cost REAL,
            erp_depto_padrao INTEGER,
            last_synced_at TEXT
          )
        ''');
      },
    ),
  );
}

SyncService _noopSync(DatabaseHelper db) => SyncService(
      db: db,
      connectivity: ConnectivityService(),
      dio: Dio(),
    );

CartNotifier _makeCart({Map<String, double>? tablePrices, required Database testDb}) {
  final helper = DatabaseHelper.forTest(testDb);
  return CartNotifier(
    repo:         OrderRepository(db: helper, sync: _noopSync(helper)),
    priceService: _FakePriceService(tablePrices ?? {}),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

Product _p(String code, double price, {double stock = 5.0, double? maxDiscount}) =>
    Product(code: code, name: 'Produto $code', price: price,
        stock: stock, maxDiscount: maxDiscount);

// ─────────────────────────────────────────────────────────────────────────────
// Testes
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  late Database db;
  late CartNotifier cart;

  setUp(() async {
    db   = await _openTestDb();
    final helper = DatabaseHelper.forTest(db);
    
    if (GetIt.I.isRegistered<ProductRepository>()) {
      GetIt.I.unregister<ProductRepository>();
    }
    GetIt.I.registerSingleton<ProductRepository>(ProductRepository(db: helper));
    
    if (GetIt.I.isRegistered<CustomerRepository>()) {
      GetIt.I.unregister<CustomerRepository>();
    }
    GetIt.I.registerSingleton<CustomerRepository>(CustomerRepository(db: helper));

    if (GetIt.I.isRegistered<AppConfigService>()) {
      GetIt.I.unregister<AppConfigService>();
    }
    GetIt.I.registerSingleton<AppConfigService>(_FakeAppConfigService());

    if (GetIt.I.isRegistered<SessionService>()) {
      GetIt.I.unregister<SessionService>();
    }
    GetIt.I.registerSingleton<SessionService>(_FakeSessionService(helper));

    cart = _makeCart(testDb: db);
  });

  tearDown(() async {
    await db.close();
    if (GetIt.I.isRegistered<ProductRepository>()) {
      GetIt.I.unregister<ProductRepository>();
    }
    if (GetIt.I.isRegistered<CustomerRepository>()) {
      GetIt.I.unregister<CustomerRepository>();
    }
    if (GetIt.I.isRegistered<AppConfigService>()) {
      GetIt.I.unregister<AppConfigService>();
    }
    if (GetIt.I.isRegistered<SessionService>()) {
      GetIt.I.unregister<SessionService>();
    }
  });

  // ── Estado inicial ─────────────────────────────────────────────────────────

  group('Estado inicial', () {
    test('carrinho começa vazio', () {
      expect(cart.items, isEmpty);
      expect(cart.hasItems, isFalse);
      expect(cart.total, 0.0);
      expect(cart.totalItemCount, 0);
      expect(cart.grandTotal, 0.0);
    });

    test('customerId e customerName começam vazios', () {
      expect(cart.customerId, '');
      expect(cart.customerName, '');
    });

    test('hasPaymentSpecies começa false', () {
      expect(cart.hasPaymentSpecies, isFalse);
    });
  });

  // ── addProduct ─────────────────────────────────────────────────────────────

  group('addProduct()', () {
    test('adiciona produto ao carrinho', () async {
      await cart.addProduct(_p('A', 10.0));
      expect(cart.items.length, 1);
      expect(cart.items.first.product.code, 'A');
      expect(cart.items.first.quantity, 1.0);
    });

    test('produto sem estoque não é adicionado', () async {
      await cart.addProduct(_p('B', 10.0, stock: 0));
      expect(cart.items, isEmpty);
    });

    test('produto repetido incrementa quantidade', () async {
      await cart.addProduct(_p('A', 10.0));
      await cart.addProduct(_p('A', 10.0), quantity: 2);
      expect(cart.items.length, 1);
      expect(cart.items.first.quantity, 3.0);
    });

    test('total reflete preço × quantidade', () async {
      await cart.addProduct(_p('A', 10.0), quantity: 3);
      expect(cart.total, closeTo(30.0, 0.001));
    });

    test('totalItemCount soma unidades de todos os itens', () async {
      await cart.addProduct(_p('A', 10.0), quantity: 2);
      await cart.addProduct(_p('B', 20.0), quantity: 3);
      expect(cart.totalItemCount, 5);
    });

    test('items retorna lista imutável (UnmodifiableListView)', () async {
      await cart.addProduct(_p('A', 10.0));
      // Tentar remover da cópia não remove do carrinho
      final snapshot = List<CartItem>.from(cart.items);
      // A lista retornada não permite mutação direta (UnmodifiableListView)
      expect(
        () => (cart.items as dynamic).removeAt(0),
        throwsUnsupportedError,
      );
      // O snapshot é uma cópia mutável separada
      snapshot.clear();
      expect(cart.items.length, 1); // carrinho intacto
    });
  });

  // ── removeItem ─────────────────────────────────────────────────────────────

  group('removeItem()', () {
    test('remove item pelo código', () async {
      await cart.addProduct(_p('A', 10.0));
      await cart.addProduct(_p('B', 20.0));
      await cart.removeItem('A');
      expect(cart.items.length, 1);
      expect(cart.items.first.product.code, 'B');
    });

    test('remover código inexistente não lança exceção', () async {
      await cart.addProduct(_p('A', 10.0));
      await expectLater(cart.removeItem('INEXISTENTE'), completes);
    });

    test('total é zero após remover todos os itens', () async {
      await cart.addProduct(_p('A', 10.0));
      await cart.removeItem('A');
      expect(cart.total, 0.0);
      expect(cart.hasItems, isFalse);
    });
  });

  // ── updateDiscount (por item) ──────────────────────────────────────────────

  group('updateDiscount() — por item', () {
    test('aplica desconto percentual 10% no item', () async {
      await cart.addProduct(_p('A', 100.0));
      await cart.updateDiscount('A', 10.0, mode: DiscountMode.percent);
      final item = cart.items.first;
      expect(item.discount, closeTo(10.0, 0.001));
      expect(item.totalPrice, closeTo(90.0, 0.001));
    });

    test('respeita maxDiscount do produto', () async {
      await cart.addProduct(_p('A', 100.0, maxDiscount: 5.0));
      await cart.updateDiscount('A', 20.0, mode: DiscountMode.percent);
      expect(cart.items.first.discount, lessThanOrEqualTo(5.0 + 0.001));
    });

    test('desconto em código inexistente não lança exceção', () async {
      await cart.addProduct(_p('A', 100.0));
      await expectLater(cart.updateDiscount('INEXISTENTE', 10.0), completes);
    });
  });

  // ── Desconto global do pedido ──────────────────────────────────────────────

  group('setOrderDiscount() — desconto global', () {
    test('desconto global percentual reduz grandTotal', () async {
      await cart.addProduct(_p('A', 100.0), quantity: 2); // total = 200
      await cart.setOrderDiscount(10.0, mode: DiscountMode.percent);
      expect(cart.orderDiscountValue, closeTo(20.0, 0.001));
      expect(cart.grandTotal, closeTo(180.0, 0.001));
    });

    test('desconto global em valor fixo', () async {
      await cart.addProduct(_p('A', 100.0), quantity: 2); // total = 200
      await cart.setOrderDiscount(30.0, mode: DiscountMode.value);
      expect(cart.orderDiscountValue, closeTo(30.0, 0.001));
      expect(cart.grandTotal, closeTo(170.0, 0.001));
    });

    test('grandTotal não fica negativo com desconto excessivo', () async {
      await cart.addProduct(_p('A', 50.0));
      await cart.setOrderDiscount(999.0, mode: DiscountMode.value);
      expect(cart.grandTotal, greaterThanOrEqualTo(0.0));
    });

    test('sem desconto: grandTotal = total', () async {
      await cart.addProduct(_p('A', 100.0));
      await cart.setOrderDiscount(0.0);
      expect(cart.grandTotal, closeTo(100.0, 0.001));
    });

    test('orderDiscountPercent equivalente ao valor aplicado', () async {
      await cart.addProduct(_p('A', 100.0)); // total = 100
      await cart.setOrderDiscount(50.0, mode: DiscountMode.value); // = 50%
      expect(cart.orderDiscountPercent, closeTo(50.0, 0.001));
    });
  });

  // ── Configurações do pedido ────────────────────────────────────────────────

  group('setPaymentSpecies()', () {
    test('persiste id, name e days', () {
      cart.setPaymentSpecies(id: 'P1', name: 'Boleto', days: 30);
      expect(cart.paymentSpeciesId, 'P1');
      expect(cart.paymentSpeciesName, 'Boleto');
      expect(cart.paymentDays, 30);
      expect(cart.hasPaymentSpecies, isTrue);
    });
  });

  group('setNatureza()', () {
    test('persiste id e descricao', () {
      cart.setNatureza(id: 'N1', descricao: 'Venda Interna');
      expect(cart.naturezaId, 'N1');
      expect(cart.naturezaDescricao, 'Venda Interna');
    });

    test('null limpa a seleção', () {
      cart.setNatureza(id: 'N1', descricao: 'Venda');
      cart.setNatureza(id: null, descricao: null);
      expect(cart.naturezaId, isNull);
    });
  });

  // ── Tabela de preço via FakePriceService ──────────────────────────────────

  group('Tabela de preço', () {
    test('usa preço da tabela quando setPriceTableManual + addProduct', () async {
      cart = _makeCart(tablePrices: {'A': 7.0}, testDb: db);
      await cart.setPriceTableManual('T1', 'Revenda');
      await cart.addProduct(_p('A', 10.0));
      // usePriceTable retorna true (default legado sem GetIt)
      expect(cart.items.first.product.price, closeTo(7.0, 0.001));
    });

    test('usa preço base quando produto não está na tabela', () async {
      cart = _makeCart(tablePrices: {}, testDb: db);
      await cart.setPriceTableManual('T1', 'Revenda');
      await cart.addProduct(_p('X', 50.0));
      expect(cart.items.first.product.price, closeTo(50.0, 0.001));
    });
  });  // fim: Tabela de preço

  // ── AllowNegativeStock ────────────────────────────────────────────────────────

  group('AllowNegativeStock', () {
    tearDown(() {
      // Garante que GetIt é limpo após cada teste do grupo
      if (GetIt.instance.isRegistered<CompanySettingsService>()) {
        GetIt.instance.unregister<CompanySettingsService>();
      }
    });

    test('padrão (sem GetIt): produto sem estoque não é adicionado', () async {
      // Sem registro no GetIt, canSellWithoutStock retorna false (comportamento legado)
      await cart.addProduct(_p('Z', 10.0, stock: 0));
      expect(cart.items, isEmpty);
    });

    test('allowNegativeStock=true: produto sem estoque é adicionado', () async {
      // Arrange: registra FakeCompanySettingsService com flag ativada
      final fakeSettings = _FakeCompanySettings(allowNegativeStock: true);
      GetIt.instance.registerSingleton<CompanySettingsService>(fakeSettings);

      // Act
      await cart.addProduct(_p('Z', 10.0, stock: 0));

      // Assert
      expect(cart.items.length, 1);
      expect(cart.items.first.product.code, 'Z');
    });

    test('allowNegativeStock=false: produto sem estoque continua bloqueado', () async {
      // Arrange: flag explicitamente desativada
      final fakeSettings = _FakeCompanySettings(allowNegativeStock: false);
      GetIt.instance.registerSingleton<CompanySettingsService>(fakeSettings);

      // Act
      await cart.addProduct(_p('Z', 10.0, stock: 0));

      // Assert
      expect(cart.items, isEmpty);
    });
  });

  // ── cloneFromOrder ─────────────────────────────────────────────────────────

  group('cloneFromOrder()', () {
    test('clona campos do pedido e gera novo UUID com precos atualizados do catalogo', () async {
      // 1) Adicionar cliente e produto no banco de dados SQLite in-memory de teste
      final helper = DatabaseHelper.forTest(db);
      final sqliteDb = await helper.database;
      
      // Cadastra cliente
      await sqliteDb.insert('customers', {
        'id': 'C1',
        'name': 'Cliente de Teste',
        'credit_limit': 1000.0,
      });

      // Cadastra produtos com precos novos (mais caros do que o pedido antigo)
      await sqliteDb.insert('products', {
        'code': 'P1',
        'name': 'Produto 1',
        'price': 150.0, // preco atualizado no catalogo
        'stock': 10.0,
      });
      await sqliteDb.insert('products', {
        'code': 'P2',
        'name': 'Produto 2',
        'price': 250.0, // preco atualizado no catalogo
        'stock': 0.0, // sem estoque
      });

      // Cria um pedido antigo (mock) para ser clonado
      final oldOrder = Order(
        id: 'ORDER_OLD',
        customerId: 'C1',
        customerName: 'Cliente de Teste',
        totalAmount: 300.0,
        syncStatus: OrderSyncStatus.synced,
        createdAt: DateTime.now().toIso8601String(),
        updatedAt: DateTime.now().toIso8601String(),
        paymentSpeciesId: 'SP1',
        paymentSpeciesName: 'Dinheiro',
        orderDiscountInput: 10.0, // antigo desconto global (sera resetado)
        orderDiscountMode: 'percent',
        items: [
          const OrderItem(
            id: 'ITEM1',
            orderId: 'ORDER_OLD',
            productCode: 'P1',
            productName: 'Produto 1',
            quantity: 2.0,
            unitPrice: 100.0, // preco antigo
            discount: 5.0, // desconto antigo por item (sera resetado)
            totalPrice: 190.0,
          ),
          const OrderItem(
            id: 'ITEM2',
            orderId: 'ORDER_OLD',
            productCode: 'P2',
            productName: 'Produto 2',
            quantity: 1.0,
            unitPrice: 200.0, // preco antigo
            totalPrice: 200.0,
          ),
          const OrderItem(
            id: 'ITEM3',
            orderId: 'ORDER_OLD',
            productCode: 'P3', // produto descontinuado (nao existe no catalogo)
            productName: 'Produto 3',
            quantity: 1.0,
            unitPrice: 300.0,
            totalPrice: 300.0,
          ),
        ],
      );

      // Executa o clone
      final result = await cart.cloneFromOrder(oldOrder);

      // Verificacoes gerais
      expect(cart.orderId, isNot(equals('ORDER_OLD'))); // novo ID gerado
      expect(cart.customerId, 'C1');
      expect(cart.customerName, 'Cliente de Teste');
      expect(cart.paymentSpeciesId, 'SP1');
      expect(cart.paymentSpeciesName, 'Dinheiro');

      // Descontos resetados (resposta 2)
      expect(cart.orderDiscountInput, 0.0);

      // Itens incluidos (P1 e P2, mas P3 descontinuado nao incluido)
      expect(cart.items.length, 2);
      
      // P1 deve ter o preco atualizado do catalogo (150.0 em vez de 100.0) e desconto resetado para 0
      final cartItem1 = cart.items.firstWhere((i) => i.product.code == 'P1');
      expect(cartItem1.product.price, 150.0);
      expect(cartItem1.quantity, 2.0);
      expect(cartItem1.discount, 0.0);

      // P2 deve ter o preco atualizado (250.0) e estoque 0.0 reportado nos avisos (resposta 1)
      final cartItem2 = cart.items.firstWhere((i) => i.product.code == 'P2');
      expect(cartItem2.product.price, 250.0);
      expect(cartItem2.quantity, 1.0);

      // Alertas coletados nos resultados de retorno (respostas 1 e 3)
      expect(result.outOfStockProducts, contains('Produto 2'));
      expect(result.missingProducts, contains('Produto 3'));
      expect(result.hasWarnings, isTrue);
    });
  });

  group('clear() behavior for loaded orders', () {
    test('nao deleta do banco de dados quando limpamos o carrinho contendo um orcamento carregado', () async {
      final helper = DatabaseHelper.forTest(db);
      final repo = OrderRepository(db: helper, sync: _noopSync(helper));
      
      // 1. Cadastra um cliente
      final sqliteDb = await helper.database;
      await sqliteDb.insert('customers', {
        'id': 'C_QUOTE',
        'name': 'Cliente Orcamento',
        'credit_limit': 1000.0,
      });

      // 2. Salva um orcamento no banco de dados
      final savedQuote = await repo.saveDraft(
        orderId: 'QUOTE_123',
        companyId: '1',
        customerId: 'C_QUOTE',
        customerName: 'Cliente Orcamento',
        items: [
          CartItem(
            product: _p('P1', 100.0),
            quantity: 1,
          ),
        ],
        isDraft: true,
      );

      // 3. Carrega o orcamento no carrinho
      await cart.loadFromOrder(savedQuote);
      expect(cart.orderId, 'QUOTE_123');
      expect(cart.hasItems, isTrue);

      // 4. Limpa o carrinho
      await cart.clear();

      // 5. Verifica se o orcamento original continua salvo no banco
      final quoteFromDb = await repo.getById('QUOTE_123');
      expect(quoteFromDb, isNotNull);
      expect(quoteFromDb!.id, 'QUOTE_123');
      expect(quoteFromDb.customerName, 'Cliente Orcamento');
    });

    test('deleta do banco de dados quando limpamos o carrinho contendo um rascunho temporario de novo pedido', () async {
      final helper = DatabaseHelper.forTest(db);
      final repo = OrderRepository(db: helper, sync: _noopSync(helper));
      
      // 1. Configura cliente no carrinho e adiciona item (gera auto-save rascunho)
      cart.setCustomer(id: 'C_TEMP', name: 'Cliente Temp');
      await cart.addProduct(_p('P1', 100.0), quantity: 1);
      
      final tempOrderId = cart.orderId;
      
      // Verifica se salvou no banco como rascunho
      final tempFromDbBefore = await repo.getById(tempOrderId);
      expect(tempFromDbBefore, isNotNull);

      // 2. Limpa o carrinho
      await cart.clear();

      // 3. Verifica se o rascunho temporario foi deletado do banco de dados
      final tempFromDbAfter = await repo.getById(tempOrderId);
      expect(tempFromDbAfter, isNull);
    });
  });
}

// ───────────────────────────────────────────────────────────────────────────────
// _FakeCompanySettings — stub para injetar allowNegativeStock no GetIt
// ───────────────────────────────────────────────────────────────────────────────

class _FakeCompanySettings extends CompanySettingsService {
  final bool _allowNegativeStockValue;
  _FakeCompanySettings({required bool allowNegativeStock})
      : _allowNegativeStockValue = allowNegativeStock;

  @override
  bool get allowNegativeStock => _allowNegativeStockValue;

  @override
  String get priceTableMode => 'none';

  @override
  bool get usePriceTable => false;

  @override
  Future<void> load() async {}

  @override
  Future<void> save(String mode, {bool allowNegativeStock = false}) async {}
}

class _FakeAppConfigService extends AppConfigService {
  @override
  Future<String?> getBranchId() async => '1';
}

class _FakeSessionService extends SessionService {
  _FakeSessionService(DatabaseHelper db) : super(db: db);

  @override
  SellerSession? get activeSession => SellerSession(
        id: 'SESS1',
        sellerId: 'V1',
        sellerName: 'Vendedor 1',
        companyId: '1',
        companyName: 'Empresa Teste',
        pinHash: 'hash',
        createdAt: DateTime.now().toIso8601String(),
      );
}

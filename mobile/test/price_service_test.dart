/// Testes unitários do PriceService.
///
/// PriceService usa SQLite (DatabaseHelper) — usamos sqflite_common_ffi
/// para rodar um banco em memória nos testes sem precisar de emulador.
///
/// Cobertura:
///   - priceTableId null → retorna basePrice
///   - priceTableId vazio → retorna basePrice
///   - produto sem entrada na tabela → retorna preço base
///   - produto com entrada na tabela → retorna preço da tabela
///   - preço de tabela zero → ignora, retorna preço base (piso de segurança)
///   - resolvePrices() batch → mapeia corretamente múltiplos produtos
///   - resolvePrices() produto não na tabela → mantém preço base
///   - getActiveTableName() tabela inexistente → null
///   - getActiveTableName() tabela existente → retorna nome

library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:coliseu_sales/core/services/price_service.dart';
import 'package:coliseu_sales/core/repositories/models/models.dart';
import 'package:coliseu_sales/core/database/database_helper.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Setup do SQLite em memória para testes
// ─────────────────────────────────────────────────────────────────────────────

Future<Database> _openTestDb() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 1,
      onCreate: (db, _) async {
        // Apenas as tabelas usadas pelo PriceService
        await db.execute('''
          CREATE TABLE product_prices (
            id             INTEGER PRIMARY KEY AUTOINCREMENT,
            product_code   TEXT NOT NULL,
            price_table_id TEXT NOT NULL,
            price          REAL NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE price_tables (
            id   TEXT PRIMARY KEY,
            name TEXT NOT NULL
          )
        ''');
      },
    ),
  );
  return db;
}

/// Helper: cria produto de teste minimal.
Product _p(String code, double price) => Product(
      code:  code,
      name:  'Produto $code',
      price: price,
      stock: 5.0,
    );

void main() {
  late Database testDb;
  late PriceService svc;
  late DatabaseHelper dbHelper;

  setUp(() async {
    testDb   = await _openTestDb();
    dbHelper = DatabaseHelper.forTest(testDb);   // ctor de teste
    svc      = PriceService(db: dbHelper);
  });

  tearDown(() async => testDb.close());

  // ─────────────────────────────────────────────────────────────────────────
  // resolvePrice()
  // ─────────────────────────────────────────────────────────────────────────

  group('resolvePrice()', () {
    test('priceTableId null → retorna preço base', () async {
      final price = await svc.resolvePrice(
        basePrice: 100.0, productCode: 'P1', priceTableId: null);
      expect(price, 100.0);
    });

    test('priceTableId vazio → retorna preço base', () async {
      final price = await svc.resolvePrice(
        basePrice: 100.0, productCode: 'P1', priceTableId: '');
      expect(price, 100.0);
    });

    test('produto sem entrada na tabela → retorna preço base', () async {
      final price = await svc.resolvePrice(
        basePrice: 100.0, productCode: 'P_SEM_TABELA', priceTableId: 'T1');
      expect(price, 100.0);
    });

    test('produto com entrada na tabela → retorna preço da tabela', () async {
      await testDb.insert('product_prices', {
        'product_code':   'P1',
        'price_table_id': 'T1',
        'price':          75.0,
      });

      final price = await svc.resolvePrice(
        basePrice: 100.0, productCode: 'P1', priceTableId: 'T1');
      expect(price, 75.0);
    });

    test('preço de tabela zero → ignora e retorna preço base', () async {
      await testDb.insert('product_prices', {
        'product_code':   'P1',
        'price_table_id': 'T1',
        'price':          0.0,   // inválido — piso de segurança
      });

      final price = await svc.resolvePrice(
        basePrice: 100.0, productCode: 'P1', priceTableId: 'T1');
      expect(price, 100.0);
    });

    test('tabela diferente do produto → retorna preço base', () async {
      await testDb.insert('product_prices', {
        'product_code':   'P1',
        'price_table_id': 'T2',   // outra tabela
        'price':          60.0,
      });

      final price = await svc.resolvePrice(
        basePrice: 100.0, productCode: 'P1', priceTableId: 'T1');
      expect(price, 100.0);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // resolvePrices() — Batch
  // ─────────────────────────────────────────────────────────────────────────

  group('resolvePrices()', () {
    test('lista vazia → mapa vazio', () async {
      final result = await svc.resolvePrices(products: [], priceTableId: 'T1');
      expect(result, isEmpty);
    });

    test('priceTableId null → todos com preço base', () async {
      final products = [_p('A', 10.0), _p('B', 20.0)];
      final result   = await svc.resolvePrices(products: products);
      expect(result['A'], 10.0);
      expect(result['B'], 20.0);
    });

    test('retorna preço de tabela para produtos presentes', () async {
      await testDb.insert('product_prices', {
        'product_code':   'A',
        'price_table_id': 'T1',
        'price':          8.0,
      });
      // Produto B não está na tabela

      final products = [_p('A', 10.0), _p('B', 20.0)];
      final result   = await svc.resolvePrices(
        products: products, priceTableId: 'T1');

      expect(result['A'], 8.0);    // preço da tabela
      expect(result['B'], 20.0);   // preço base (não está na tabela)
    });

    test('preço de tabela zero → mant\xe9m preço base', () async {
      await testDb.insert('product_prices', {
        'product_code':   'A',
        'price_table_id': 'T1',
        'price':          0.0,
      });

      final result = await svc.resolvePrices(
        products: [_p('A', 10.0)], priceTableId: 'T1');
      expect(result['A'], 10.0);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // getActiveTableName()
  // ─────────────────────────────────────────────────────────────────────────

  group('getActiveTableName()', () {
    test('null → retorna null', () async {
      final name = await svc.getActiveTableName(null);
      expect(name, isNull);
    });

    test('id vazio → retorna null', () async {
      final name = await svc.getActiveTableName('');
      expect(name, isNull);
    });

    test('id inexistente → retorna null', () async {
      final name = await svc.getActiveTableName('INEXISTENTE');
      expect(name, isNull);
    });

    test('id existente → retorna nome da tabela', () async {
      await testDb.insert('price_tables', {'id': 'T1', 'name': 'Preço Revenda'});
      final name = await svc.getActiveTableName('T1');
      expect(name, 'Preço Revenda');
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:dio/dio.dart';
import 'package:coliseu_sales/core/database/database_helper.dart';
import 'package:coliseu_sales/core/repositories/performance_repository.dart';

void main() {
  // Initialize ffi for testing database on desktop/test runner
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('Sync and Save performance test', () async {
    final db = await openDatabase(inMemoryDatabasePath, version: 19,
        onCreate: (db, version) async {
      await db.execute('''
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
    });

    final dbHelper = DatabaseHelper.forTest(db);
    final perfRepo = PerformanceRepository(dbHelper);

    // Call real VPS endpoint
    final dio = Dio(BaseOptions(
      baseUrl: 'https://licencas.coliseusistemas.com.br',
      headers: {
        'API-Key': 'COL-NZ2Q-U4ZD-CDDH',
        'X-Branch-Id': 'a5ade2d9-a169-40f5-922a-704262867dff',
      },
    ));

    print('Calling performance endpoint...');
    final response = await dio.get('/api/sync/performance', queryParameters: {
      'sellerId': '105',
      'month': 5,
      'year': 2026,
    });

    print('Response status: ${response.statusCode}');
    print('Response data: ${response.data}');

    final body = response.data;
    final apiData = body['data'] as Map<String, dynamic>? ?? <String, dynamic>{};

    final companyId = 'a5ade2d9-a169-40f5-922a-704262867dff';
    final sellerId = '105';

    // Upsert via DatabaseHelper
    await dbHelper.upsertSellerKpis({
      'company_id':         companyId,
      'seller_id':          sellerId,
      'month':              (apiData['month'] as num?)?.toInt() ?? 5,
      'year':               (apiData['year'] as num?)?.toInt() ?? 2026,
      'venda_diaria':       (apiData['vendaDiaria'] as num?)?.toDouble() ?? 0,
      'venda_mensal':       (apiData['vendaMensal'] as num?)?.toDouble() ?? 0,
      'comissao_diaria':    (apiData['comissaoDiaria'] as num?)?.toDouble() ?? 0,
      'comissao_mensal':    (apiData['comissaoMensal'] as num?)?.toDouble() ?? 0,
      'meta_diaria':        (apiData['metaDiaria'] as num?)?.toDouble() ?? 0,
      'meta_mensal':        (apiData['metaMensal'] as num?)?.toDouble() ?? 0,
      'servico_mensal':     (apiData['servicoMensal'] as num?)?.toDouble() ?? 0,
      'comissao_sv_mensal': (apiData['comissaoSvMensal'] as num?)?.toDouble() ?? 0,
      'total_diario':       (apiData['totalDiario'] as num?)?.toDouble() ?? 0,
      'total_mensal':       (apiData['totalMensal'] as num?)?.toDouble() ?? 0,
      'comissao_diaria_r':  (apiData['comissaoDiariaR'] as num?)?.toDouble() ?? 0,
      'comissao_mensal_r':  (apiData['comissaoMensalR'] as num?)?.toDouble() ?? 0,
      'synced_at':          apiData['syncedAt']?.toString() ?? '',
    });

    print('Upsert done.');

    // Query it back
    final kpis = await perfRepo.get(companyId, sellerId, month: 5, year: 2026);
    if (kpis != null) {
      print('Retrieved KPIs:');
      print('vendaMensal: ${kpis.vendaMensal}');
      print('syncedAt: ${kpis.syncedAt}');
      print('hasData: ${kpis.hasData}');
    } else {
      print('KPIs not found in DB!');
    }

    await db.close();
  });
}

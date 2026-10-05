/// Banco local (SQLite).
///
///  outbox     leituras ainda não confirmadas pela API (fila offline, ordem preservada)
///  products   catálogo para identificar códigos sem internet
///  barcodes   código de barras → produto + fator da embalagem
///  documents  último detalhe recebido de cada documento (abrir offline o que já estava reservado)
library;

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class LocalDb {
  LocalDb._(this.db);
  final Database db;

  static Future<LocalDb> open() async {
    final path = p.join(await getDatabasesPath(), 'coliseu_estoque.db');
    final db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE outbox (
            id          TEXT PRIMARY KEY,   -- UUID do evento (idempotência na API)
            document_id TEXT NOT NULL,
            round       INTEGER NOT NULL,
            barcode     TEXT NOT NULL,      -- código como foi lido/digitado
            product_id  TEXT,               -- resolução local (para exibir offline)
            explicit_product INTEGER NOT NULL DEFAULT 0, -- 1 = código interno digitado: envia productErpId
            qty         REAL NOT NULL,      -- embalagens lidas (a API aplica o fator)
            units       REAL NOT NULL,      -- unidades já com fator (só para exibir offline)
            origin      TEXT NOT NULL,
            scanned_at  TEXT NOT NULL,
            attempts    INTEGER NOT NULL DEFAULT 0,
            last_error  TEXT
          )''');
        await db.execute('CREATE INDEX outbox_doc ON outbox (document_id, scanned_at)');
        await db.execute('''
          CREATE TABLE products (
            erp_id      TEXT PRIMARY KEY,
            description TEXT NOT NULL,
            unit        TEXT,
            active      INTEGER NOT NULL DEFAULT 1
          )''');
        await db.execute('''
          CREATE TABLE barcodes (
            barcode TEXT PRIMARY KEY,
            erp_id  TEXT NOT NULL,
            factor  REAL NOT NULL DEFAULT 1
          )''');
        await db.execute('''
          CREATE TABLE documents (
            id         TEXT PRIMARY KEY,
            json       TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )''');
      },
    );
    return LocalDb._(db);
  }

  // ── Catálogo ─────────────────────────────────────────────────────────────

  Future<({String productErpId, String description, double factor})?> resolve(String code) async {
    final b = await db.rawQuery(
      'SELECT b.erp_id, b.factor, p.description FROM barcodes b LEFT JOIN products p ON p.erp_id = b.erp_id WHERE b.barcode = ?',
      [code],
    );
    if (b.isNotEmpty) {
      return (
        productErpId: b.first['erp_id'] as String,
        description: (b.first['description'] as String?) ?? '',
        factor: (b.first['factor'] as num).toDouble(),
      );
    }
    // Código interno digitado manualmente.
    final pr = await db.query('products', where: 'erp_id = ?', whereArgs: [code], limit: 1);
    if (pr.isNotEmpty) {
      return (productErpId: code, description: pr.first['description'] as String, factor: 1.0);
    }
    return null;
  }

  Future<String?> productName(String erpId) async {
    final r = await db.query('products', columns: ['description'], where: 'erp_id = ?', whereArgs: [erpId], limit: 1);
    return r.isEmpty ? null : r.first['description'] as String;
  }

  Future<void> upsertProducts(List<Map<String, dynamic>> items) async {
    final batch = db.batch();
    for (final i in items) {
      batch.insert('products', {
        'erp_id': i['erpId'],
        'description': i['description'] ?? '',
        'unit': i['unit'],
        'active': i['active'] == false ? 0 : 1,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<void> upsertBarcodes(List<Map<String, dynamic>> items) async {
    final batch = db.batch();
    for (final i in items) {
      batch.insert('barcodes', {
        'barcode': i['barcode'],
        'erp_id': i['erpId'],
        'factor': double.tryParse('${i['factor']}') ?? 1,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<int> productCount() async =>
      Sqflite.firstIntValue(await db.rawQuery('SELECT count(*) FROM products')) ?? 0;

  // ── Documentos em cache ──────────────────────────────────────────────────

  Future<void> cacheDocument(String id, String json) => db.insert(
        'documents',
        {'id': id, 'json': json, 'updated_at': DateTime.now().toIso8601String()},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<String?> cachedDocument(String id) async {
    final r = await db.query('documents', where: 'id = ?', whereArgs: [id], limit: 1);
    return r.isEmpty ? null : r.first['json'] as String;
  }

  // ── Fila de leituras ─────────────────────────────────────────────────────

  Future<void> enqueue(Map<String, Object?> row) => db.insert('outbox', row);

  Future<List<Map<String, Object?>>> pendingFor(String documentId) =>
      db.query('outbox', where: 'document_id = ?', whereArgs: [documentId], orderBy: 'scanned_at');

  Future<List<String>> documentsWithPending() async =>
      (await db.rawQuery('SELECT DISTINCT document_id FROM outbox')).map((r) => r['document_id'] as String).toList();

  Future<int> pendingCount() async => Sqflite.firstIntValue(await db.rawQuery('SELECT count(*) FROM outbox')) ?? 0;

  Future<void> removeFromOutbox(List<String> ids) async {
    if (ids.isEmpty) return;
    await db.delete('outbox', where: 'id IN (${List.filled(ids.length, '?').join(',')})', whereArgs: ids);
  }

  Future<void> markAttempt(List<String> ids, String error) async {
    if (ids.isEmpty) return;
    await db.rawUpdate(
      'UPDATE outbox SET attempts = attempts + 1, last_error = ? WHERE id IN (${List.filled(ids.length, '?').join(',')})',
      [error, ...ids],
    );
  }

  /// Unidades ainda na fila por produto (somadas à contagem confirmada para exibir offline).
  Future<Map<String, double>> pendingUnits(String documentId, int round) async {
    final rows = await db.rawQuery(
      'SELECT product_id, sum(units) AS u FROM outbox WHERE document_id = ? AND round = ? AND product_id IS NOT NULL GROUP BY product_id',
      [documentId, round],
    );
    return {for (final r in rows) r['product_id'] as String: (r['u'] as num).toDouble()};
  }
}

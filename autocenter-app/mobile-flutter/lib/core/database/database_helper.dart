import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('autocenter.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 12,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future _createDB(Database db, int version) async {
    const idType = 'INTEGER PRIMARY KEY AUTOINCREMENT';
    const textType = 'TEXT NOT NULL';
    const doubleType = 'REAL NOT NULL';
    
    await db.execute('''
CREATE TABLE vehicles (
  id $idType,
  id_cliente INTEGER,
  id_veiculo INTEGER,
  brand $textType,
  model $textType,
  plate $textType,
  ano_fabrica INTEGER,
  ano_modelo INTEGER,
  cor TEXT,
  obs TEXT,
  numero TEXT,
  numero_chassi TEXT,
  id_seguradora INTEGER,
  status INTEGER,
  numero_1 TEXT,
  numero_2 TEXT,
  combustivel TEXT
)
''');

    await db.execute('''
CREATE TABLE drafts (
  id $idType,
  vehicle_plate $textType,
  customer_name TEXT,
  status $textType,
  created_at $textType
)
''');

    await db.execute('''
CREATE TABLE draft_photos (
  id $idType,
  draft_id INTEGER NOT NULL,
  path $textType,
  type $textType,
  FOREIGN KEY (draft_id) REFERENCES drafts (id) ON DELETE CASCADE
)
''');

    await db.execute('''
CREATE TABLE draft_items (
  id $idType,
  draft_id INTEGER NOT NULL,
  product_code $textType,
  product_name $textType,
  quantity $doubleType,
  unit_price $doubleType,
  discount $doubleType,
  FOREIGN KEY (draft_id) REFERENCES drafts (id) ON DELETE CASCADE
)
''');

    await db.execute('''
CREATE TABLE customers (
  id $idType,
  erp_id INTEGER UNIQUE,
  local_id TEXT UNIQUE,
  name $textType,
  fantasy_name TEXT,
  cpf_cnpj TEXT,
  phone TEXT,
  phone2 TEXT,
  email TEXT,
  city TEXT,
  address TEXT,
  street TEXT,
  number TEXT,
  complement TEXT,
  neighborhood TEXT,
  zip TEXT,
  state TEXT,
  active INTEGER NOT NULL DEFAULT 1,
  sync_status TEXT NOT NULL DEFAULT 'synced'
)
''');

    await db.execute('''
CREATE TABLE catalog (
  id $idType,
  erp_id INTEGER NOT NULL UNIQUE,
  name $textType,
  category TEXT,
  price REAL NOT NULL DEFAULT 0.0,
  brand TEXT,
  code TEXT,
  active INTEGER NOT NULL DEFAULT 1,
  stock REAL NOT NULL DEFAULT 0.0,
  unit TEXT,
  reference TEXT,
  item_type TEXT NOT NULL DEFAULT 'PART'
)
''');

    await db.execute('''
CREATE TABLE sync_queue (
  id $idType,
  item_type $textType,
  item_id $textType,
  operation $textType,
  payload $textType,
  status TEXT NOT NULL DEFAULT 'PENDING',
  attempts INTEGER NOT NULL DEFAULT 0,
  error_message TEXT,
  created_at $textType
)
''');

    await db.execute('''
CREATE TABLE service_orders (
  id TEXT PRIMARY KEY,
  quote_id TEXT,
  device_id TEXT NOT NULL,
  plate TEXT NOT NULL,
  customer_id INTEGER,
  customer_name TEXT,
  customer_phone TEXT,
  status TEXT NOT NULL DEFAULT 'ABERTA',
  total_amount REAL NOT NULL DEFAULT 0.0,
  observation TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  sync_status TEXT NOT NULL DEFAULT 'synced',
  seller_id INTEGER,
  natureza_id TEXT,
  payment_condition_id TEXT,
  payment_species_id TEXT,
  driver TEXT,
  odometer REAL,
  fuel_level REAL
)
''');

    await db.execute('''
CREATE TABLE service_order_items (
  id TEXT PRIMARY KEY,
  service_order_id TEXT NOT NULL,
  product_code TEXT NOT NULL,
  product_description TEXT NOT NULL,
  quantity REAL NOT NULL,
  unit_price REAL NOT NULL,
  total_price REAL NOT NULL,
  item_type TEXT NOT NULL DEFAULT 'PART',
  technician_id INTEGER,
  created_at TEXT NOT NULL,
  FOREIGN KEY (service_order_id) REFERENCES service_orders (id) ON DELETE CASCADE
)
''');

    await db.execute('''
CREATE TABLE service_order_photos (
  id TEXT PRIMARY KEY,
  service_order_id TEXT NOT NULL,
  photo_url TEXT NOT NULL,
  photo_type TEXT,
  created_at TEXT NOT NULL,
  FOREIGN KEY (service_order_id) REFERENCES service_orders (id) ON DELETE CASCADE
)
''');

    await db.execute('''
CREATE TABLE service_order_checklist (
  id TEXT PRIMARY KEY,
  service_order_id TEXT NOT NULL,
  item_name TEXT NOT NULL,
  status TEXT NOT NULL,
  observation TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (service_order_id) REFERENCES service_orders (id) ON DELETE CASCADE
)
''');

    await db.execute('''
CREATE TABLE technicians (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  active INTEGER NOT NULL DEFAULT 1
)
''');

    await db.execute('''
CREATE TABLE sellers (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  email TEXT,
  pin TEXT,
  max_discount REAL,
  active INTEGER NOT NULL DEFAULT 1
)
''');

    await db.execute('''
CREATE TABLE payment_species (
  id INTEGER PRIMARY KEY,
  description TEXT NOT NULL,
  tipo TEXT
)
''');

    await db.execute('''
CREATE TABLE payment_conditions (
  id TEXT PRIMARY KEY,
  especie_id INTEGER,
  forma_id INTEGER,
  descricao TEXT NOT NULL
)
''');

    await db.execute('''
CREATE TABLE naturezas_operacao (
  id INTEGER PRIMARY KEY,
  descricao TEXT NOT NULL,
  descricao_nota TEXT,
  codigo_fiscal TEXT,
  es INTEGER,
  processo INTEGER,
  tipo INTEGER,
  mob_ordem INTEGER
)
''');
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    const idType = 'INTEGER PRIMARY KEY AUTOINCREMENT';
    const textType = 'TEXT NOT NULL';

    if (oldVersion < 2) {
      await db.execute('''
CREATE TABLE customers (
  id $idType,
  erp_id INTEGER NOT NULL UNIQUE,
  name $textType,
  fantasy_name TEXT,
  cpf_cnpj TEXT,
  phone TEXT,
  phone2 TEXT,
  email TEXT,
  city TEXT,
  address TEXT,
  active INTEGER NOT NULL DEFAULT 1
)
''');
      print("[DB] Upgrade executado: Versão \$oldVersion -> \$newVersion (Tabela customers Criada).");
    }

    if (oldVersion < 3) {
      await db.execute('''
CREATE TABLE catalog (
  id $idType,
  erp_id INTEGER NOT NULL UNIQUE,
  name $textType,
  category TEXT,
  price REAL NOT NULL DEFAULT 0.0,
  brand TEXT,
  code TEXT,
  active INTEGER NOT NULL DEFAULT 1
)
''');
      print("[DB] Upgrade executado: Versão \$oldVersion -> \$newVersion (Tabela catalog Criada).");
    }
    
    if (oldVersion < 4) {
      await db.execute('ALTER TABLE draft_items ADD COLUMN product_name TEXT NOT NULL DEFAULT "Desconhecido"');
    }

    if (oldVersion < 5) {
      await db.execute('ALTER TABLE drafts ADD COLUMN customer_name TEXT');
    }

    if (oldVersion < 6) {
      // 1. Criar tabela sync_queue
      await db.execute('''
CREATE TABLE sync_queue (
  id $idType,
  item_type $textType,
  item_id $textType,
  operation $textType,
  payload $textType,
  status TEXT NOT NULL DEFAULT 'PENDING',
  attempts INTEGER NOT NULL DEFAULT 0,
  error_message TEXT,
  created_at $textType
)
''');

      // 2. Adicionar novas colunas ao catálogo
      await db.execute('ALTER TABLE catalog ADD COLUMN stock REAL DEFAULT 0.0');
      await db.execute('ALTER TABLE catalog ADD COLUMN unit TEXT');
      await db.execute('ALTER TABLE catalog ADD COLUMN reference TEXT');
      await db.execute('ALTER TABLE catalog ADD COLUMN item_type TEXT DEFAULT "PART"');

      // 3. Migrar tabela de customers para suportar erp_id nulo e local_id
      await db.execute('ALTER TABLE customers RENAME TO customers_old');
      await db.execute('''
CREATE TABLE customers (
  id $idType,
  erp_id INTEGER UNIQUE,
  local_id TEXT UNIQUE,
  name $textType,
  fantasy_name TEXT,
  cpf_cnpj TEXT,
  phone TEXT,
  phone2 TEXT,
  email TEXT,
  city TEXT,
  address TEXT,
  street TEXT,
  number TEXT,
  complement TEXT,
  neighborhood TEXT,
  zip TEXT,
  state TEXT,
  active INTEGER NOT NULL DEFAULT 1,
  sync_status TEXT NOT NULL DEFAULT 'synced'
)
''');

      // Copiar dados anteriores
      await db.execute('''
INSERT INTO customers (id, erp_id, name, fantasy_name, cpf_cnpj, phone, phone2, email, city, address, active, sync_status)
SELECT id, erp_id, name, fantasy_name, cpf_cnpj, phone, phone2, email, city, address, active, 'synced'
FROM customers_old
''');

      await db.execute('DROP TABLE customers_old');
      print("[DB] Upgrade executado: Versão \$oldVersion -> \$newVersion (v6 migração concluída).");
    }

    if (oldVersion < 7) {
      print("[DB] Upgrade executado: Versão \$oldVersion -> \$newVersion (v7 migração concluída).");
    }

    if (oldVersion < 8) {
      await db.execute('''
CREATE TABLE service_orders (
  id TEXT PRIMARY KEY,
  quote_id TEXT,
  device_id TEXT NOT NULL,
  plate TEXT NOT NULL,
  customer_id INTEGER,
  customer_name TEXT,
  customer_phone TEXT,
  status TEXT NOT NULL DEFAULT 'ABERTA',
  total_amount REAL NOT NULL DEFAULT 0.0,
  observation TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  sync_status TEXT NOT NULL DEFAULT 'synced'
)
''');

      await db.execute('''
CREATE TABLE service_order_items (
  id TEXT PRIMARY KEY,
  service_order_id TEXT NOT NULL,
  product_code TEXT NOT NULL,
  product_description TEXT NOT NULL,
  quantity REAL NOT NULL,
  unit_price REAL NOT NULL,
  total_price REAL NOT NULL,
  item_type TEXT NOT NULL DEFAULT 'PART',
  technician_id INTEGER,
  created_at TEXT NOT NULL,
  FOREIGN KEY (service_order_id) REFERENCES service_orders (id) ON DELETE CASCADE
)
''');

      await db.execute('''
CREATE TABLE service_order_photos (
  id TEXT PRIMARY KEY,
  service_order_id TEXT NOT NULL,
  photo_url TEXT NOT NULL,
  photo_type TEXT,
  created_at TEXT NOT NULL,
  FOREIGN KEY (service_order_id) REFERENCES service_orders (id) ON DELETE CASCADE
)
''');

      await db.execute('''
CREATE TABLE service_order_checklist (
  id TEXT PRIMARY KEY,
  service_order_id TEXT NOT NULL,
  item_name TEXT NOT NULL,
  status TEXT NOT NULL,
  observation TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (service_order_id) REFERENCES service_orders (id) ON DELETE CASCADE
)
''');
      print("[DB] Upgrade executado: Versão \$oldVersion -> \$newVersion (v8 tabelas OS criadas).");
    }

    if (oldVersion < 9) {
      await db.execute('''
CREATE TABLE technicians (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  active INTEGER NOT NULL DEFAULT 1
)
''');
      print("[DB] Upgrade executado: Versão \$oldVersion -> \$newVersion (v9 tabela technicians criada).");
    }

    if (oldVersion < 10) {
      await db.execute('''
CREATE TABLE sellers (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  email TEXT,
  pin TEXT,
  max_discount REAL,
  active INTEGER NOT NULL DEFAULT 1
)
''');
      await db.execute('ALTER TABLE service_orders ADD COLUMN seller_id INTEGER');
      print("[DB] Upgrade executado: Versão \$oldVersion -> \$newVersion (v10 tabela sellers criada e coluna seller_id adicionada a service_orders).");
    }

    if (oldVersion < 11) {
      await db.execute('''
CREATE TABLE payment_species (
  id INTEGER PRIMARY KEY,
  description TEXT NOT NULL,
  tipo TEXT
)
''');
      await db.execute('''
CREATE TABLE payment_conditions (
  id TEXT PRIMARY KEY,
  especie_id INTEGER,
  forma_id INTEGER,
  descricao TEXT NOT NULL
)
''');
      await db.execute('''
CREATE TABLE naturezas_operacao (
  id INTEGER PRIMARY KEY,
  descricao TEXT NOT NULL,
  descricao_nota TEXT,
  codigo_fiscal TEXT,
  es INTEGER,
  processo INTEGER,
  tipo INTEGER,
  mob_ordem INTEGER
)
''');
      await db.execute('ALTER TABLE service_orders ADD COLUMN natureza_id TEXT');
      await db.execute('ALTER TABLE service_orders ADD COLUMN payment_condition_id TEXT');
      await db.execute('ALTER TABLE service_orders ADD COLUMN payment_species_id TEXT');
      print("[DB] Upgrade executado: Versão \$oldVersion -> \$newVersion (v11 tabelas de configuração ERP criadas).");
    }

    if (oldVersion < 12) {
      await db.execute('ALTER TABLE service_orders ADD COLUMN driver TEXT');
      await db.execute('ALTER TABLE service_orders ADD COLUMN odometer REAL');
      await db.execute('ALTER TABLE service_orders ADD COLUMN fuel_level REAL');
      print("[DB] Upgrade executado: Versão \$oldVersion -> \$newVersion (v12 colunas driver, odometer e fuel_level adicionadas a service_orders).");
    }
  }

  Future close() async {
    final db = await instance.database;
    db.close();
  }
}

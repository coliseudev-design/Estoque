import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void initSqliteFfi() {
  sqfliteFfiInit();
}

DatabaseFactory get ffiDatabaseFactory => databaseFactoryFfi;

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void initDesktopDatabase() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
}

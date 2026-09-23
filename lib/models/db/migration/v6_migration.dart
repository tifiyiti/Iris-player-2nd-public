import 'package:drift/drift.dart';
import 'package:iris/models/db/app_database.dart';

class MigrationV6 {
  final AppDatabase db;

  MigrationV6(this.db);

  Future<void> run(Migrator m) async {
    await db.transaction(() async {
      await _addNameToSources(m);
    });
  }

  Future<void> _addNameToSources(Migrator m) async {
    if (await _columnExists('media_lib_sources', 'name')) return;
    await m.addColumn(db.mediaLibSourcesTable, db.mediaLibSourcesTable.name);
  }

  Future<bool> _columnExists(String table, String column) async {
    final rows = await db.customSelect('PRAGMA table_info($table)').get();
    return rows.any((row) => row.read<String>('name') == column);
  }
}

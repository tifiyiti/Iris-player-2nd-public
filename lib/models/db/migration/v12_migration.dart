import 'package:drift/drift.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/utils/logger.dart';
final areaKeyLog = AreaKeyLog(LogKeys.legacyDb);

/// Schema v12: introduce the metadata-driven settings subsystem.
///
/// Three ADDITIVE tables; no existing table or column is touched:
///  - setting_defs   : metadata registry (one row per setting)
///  - setting_values : sparse user overrides (only changed settings)
///  - feature_flags  : runtime feature gates (stage/default/userOverride)
///
/// Each creation is existence-guarded so the migration is safely re-entrant.
class MigrationV12 {
  final AppDatabase db;

  MigrationV12(this.db);

  Future<void> run(Migrator m) async {
    await _createIfMissing(db.settingDefsTable, m);
    await _createIfMissing(db.settingValuesTable, m);
    await _createIfMissing(db.featureFlagsTable, m);
  }

  Future<void> _createIfMissing(dynamic table, Migrator m) async {
    final String name = table.actualTableName as String;
    if (!await _tableExists(name)) {
      areaKeyLog.i('MigrationV12: creating $name');
      await m.createTable(table as TableInfo<Table, dynamic>);
    }
  }

  Future<bool> _tableExists(String name) async {
    final rows = await db.customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      variables: <Variable>[Variable.withString(name)],
    ).get();
    return rows.isNotEmpty;
  }
}

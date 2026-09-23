import 'package:drift/drift.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/utils/logger.dart';
final areaKeyLog = AreaKeyLog(LogKeys.legacyDb);

/// Schema v10: capture the queue-generation rule on scenarios.
///
/// Adds `scenario.original_sort_field` (nullable textEnum) so the order menu
/// can restore the "Original" order — the sort the user saw in the source view
/// when the scenario was first populated.
class MigrationV10 {
  final AppDatabase db;

  MigrationV10(this.db);

  Future<void> run(Migrator m) async {
    if (!await _columnExists('scenario', 'original_sort_field')) {
      areaKeyLog.i('MigrationV10: adding scenario.original_sort_field');
      await m.addColumn(db.scenariosTable, db.scenariosTable.originalSortField);
    }
  }

  Future<bool> _columnExists(String table, String column) async {
    final rows = await db
        .customSelect(
          'PRAGMA table_info($table)',
        )
        .get();
    return rows.any((row) => row.read<String>('name') == column);
  }
}

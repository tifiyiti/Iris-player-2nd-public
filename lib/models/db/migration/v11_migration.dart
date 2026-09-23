import 'package:drift/drift.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/utils/logger.dart';
final areaKeyLog = AreaKeyLog(LogKeys.legacyDb);

/// Schema v11: add the source-internal-ordering preference on scenarios.
///
/// Adds `scenario.source_internal_first` (boolean, default true) so the queue
/// can toggle between path-grouped (parentPath, sortField, name) ordering and
/// plain per-source field sorting (D5/D6).
class MigrationV11 {
  final AppDatabase db;

  MigrationV11(this.db);

  Future<void> run(Migrator m) async {
    if (!await _columnExists('scenario', 'source_internal_first')) {
      areaKeyLog.i('MigrationV11: adding scenario.source_internal_first');
      await m.addColumn(
        db.scenariosTable,
        db.scenariosTable.sourceInternalFirst,
      );
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

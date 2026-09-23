import 'package:drift/drift.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/utils/logger.dart';

final _log = AreaKeyLog(LogKeys.legacyDb);

/// Schema v20: per-directory recursive-scan status enum.
///
/// Adds `scan_state` TEXT NOT NULL DEFAULT 'notScan' to `media_nodes`
/// (`notScan | scanning | scanDone | error`). Existing `isScanDone` +
/// `lastScanAt` columns stay and are kept in sync with `scanDone` by the
/// DAO write path, so the scan-resume logic is unaffected. Re-entrant.
class MigrationV20 {
  final AppDatabase db;

  MigrationV20(this.db);

  Future<void> run(Migrator m) async {
    final cols = await _columnNames('media_nodes');
    if (cols == null) return;
    if (!cols.contains('scan_state')) {
      _log.i('MigrationV20: adding media_nodes.scan_state');
      await m.addColumn(db.mediaNodesTable, db.mediaNodesTable.scanState);
    }
  }

  Future<Set<String>?> _columnNames(String table) async {
    final tables = await db.customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      variables: <Variable>[Variable.withString(table)],
    ).get();
    if (tables.isEmpty) return null;
    final rows = await db.customSelect('PRAGMA table_info($table)').get();
    return rows.map((row) => row.read<String>('name')).toSet();
  }
}

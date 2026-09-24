import 'package:drift/drift.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/utils/logger.dart';

final _log = AreaKeyLog(LogKeys.legacyDb);

/// Schema v24: history-restore budget on `media_nodes`.
///
/// Adds a nullable `history_restore_budget` column. It lets the open-resume
/// path consult HistoryStore a bounded number of times when the row carries
/// no usable position (≤0) — restoring a real single video whose progress was
/// momentarily cleared or raced to 0 by a file-switch save — while a VM
/// sequential-advance pre-write (0 with budget 0) stays an explicit
/// "from the beginning" that history never resurrects.
///
/// Re-entrant: added only when missing (PRAGMA table_info).
class MigrationV24 {
  final AppDatabase db;

  MigrationV24(this.db);

  Future<void> run(Migrator m) async {
    final columns = await _columnNames('media_nodes');
    if (columns == null) {
      // Fresh installs create the table with the column via onCreate.
      return;
    }
    if (!columns.contains('history_restore_budget')) {
      _log.i('MigrationV24: adding media_nodes.history_restore_budget');
      try {
        await db.customStatement(
          'ALTER TABLE media_nodes ADD COLUMN history_restore_budget INTEGER NULL',
        );
      } catch (e) {
        // Do NOT swallow: a missing column while the version advances would
        // break every later read/write. Rethrowing rolls the migration back so
        // the next open retries.
        _log.e('MigrationV24: add column failed', e);
        rethrow;
      }
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

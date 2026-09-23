import 'package:drift/drift.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/utils/logger.dart';

final _log = AreaKeyLog(LogKeys.legacyDb);

/// Schema v29: `storages_table.resolved_hosts` — JSON list of recently
/// resolved WebDAV hosts (most-recent first), superseding the single-value
/// `resolved_host` column.
///
/// The legacy column is deliberately KEPT (not dropped) so an older build can
/// still read its cached host after a rollback.
///
/// Re-entrant: the column is only added when missing (guarded via
/// PRAGMA table_info), and the back-fill only touches rows that still have a
/// NULL list, so re-running never duplicates or clobbers a populated list.
class MigrationV29 {
  final AppDatabase db;

  MigrationV29(this.db);

  static const _table = 'storages_table';
  static const _column = 'resolved_hosts';

  Future<void> run(Migrator m) async {
    final columns = await _columnNames(_table);
    if (columns == null) {
      // Table itself absent (fresh installs create it with the column via
      // onCreate); nothing to upgrade here.
      return;
    }

    if (!columns.contains(_column)) {
      _log.i('MigrationV29: adding $_table.$_column');
      await db.customStatement(
        'ALTER TABLE $_table ADD COLUMN $_column TEXT NULL',
      );
    }

    // Back-fill the legacy single value into list form. The cached value is
    // always a bare IPv4 literal or hostname, so string concatenation yields
    // a valid JSON array without needing SQLite's JSON1 extension.
    await db.customStatement(
      "UPDATE $_table SET $_column = '[\"' || resolved_host || '\"]' "
      "WHERE $_column IS NULL "
      "AND resolved_host IS NOT NULL AND resolved_host <> ''",
    );
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

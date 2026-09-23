import 'package:drift/drift.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/utils/logger.dart';

final _log = AreaKeyLog(LogKeys.legacyDb);

/// Schema v40: `scenario_queue_entries.placeholder_*` — the identity of an
/// UNAVAILABLE row.
///
/// The derived index keeps a row for every visible element, including the
/// `available: false` placeholders the resolver emits for an empty folder
/// source, a missing file-kind source or a missing explicit item (D28). Such a
/// row is not backed by a `media_nodes` row, so its `storage_id`/`path` — all the
/// read side needs to rebuild the greyed placeholder — is persisted with it.
///
/// Re-entrant: each column is added only when missing (guarded via
/// PRAGMA table_info), so a fresh install (created with the columns by
/// onCreate) and an upgraded database converge on the same shape.
class MigrationV40 {
  final AppDatabase db;

  MigrationV40(this.db);

  static const _table = 'scenario_queue_entries';
  static const _columns = <String, String>{
    'placeholder_storage_id': 'TEXT NULL',
    'placeholder_path': 'TEXT NULL',
  };

  Future<void> run(Migrator m) async {
    final columns = await _columnNames(_table);
    if (columns == null) {
      // Table itself absent (fresh installs create it with the columns via
      // onCreate); nothing to upgrade here.
      return;
    }
    for (final entry in _columns.entries) {
      if (columns.contains(entry.key)) continue;
      _log.i('MigrationV40: adding $_table.${entry.key}');
      await db.customStatement(
        'ALTER TABLE $_table ADD COLUMN ${entry.key} ${entry.value}',
      );
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

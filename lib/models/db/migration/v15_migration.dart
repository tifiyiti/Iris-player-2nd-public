import 'package:drift/drift.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/utils/logger.dart';

final _log = AreaKeyLog(LogKeys.legacyDb);

/// Schema v15: deep-probe media info columns on `media_nodes`.
///
/// Adds three nullable columns used by the optional scan-time probe and
/// the lazy playback backfill:
/// - `width`  — video frame width in pixels
/// - `height` — video frame height in pixels
/// - `pixel_count` — cached width * height for resolution sorting
///
/// NULL means "not probed yet"; sorting treats NULLs last regardless of
/// direction, and playback backfills values over time.
///
/// Re-entrant: each column is only added when missing (guarded via
/// PRAGMA table_info).
class MigrationV15 {
  final AppDatabase db;

  MigrationV15(this.db);

  static const _columns = <String, String>{
    'width': 'INTEGER NULL',
    'height': 'INTEGER NULL',
    'pixel_count': 'INTEGER NULL',
  };

  Future<void> run(Migrator m) async {
    final columns = await _columnNames('media_nodes');
    if (columns == null) {
      // Table itself absent (fresh installs create it with the columns via
      // onCreate); nothing to upgrade here.
      return;
    }

    for (final entry in _columns.entries) {
      if (columns.contains(entry.key)) continue;
      _log.i('MigrationV15: adding media_nodes.${entry.key}');
      await db.customStatement(
        'ALTER TABLE media_nodes ADD COLUMN ${entry.key} ${entry.value}',
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

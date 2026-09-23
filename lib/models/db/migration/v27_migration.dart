import 'package:drift/drift.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/utils/logger.dart';

final _log = AreaKeyLog(LogKeys.legacyDb);

/// Schema v27: per-segment volume split on `bg_mapping_segments`.
///
/// - `fg_percent` / `bg_percent` (both NULL-able): the fg/副音 volume shares
///   that apply while the segment plays. NULL = fall back to the per-media
///   override, then the global pair (so every existing row is unchanged).
///   `bg_percent = 0` keeps the file but silences 副音 for the span.
///
/// Re-entrant: each column is created only when absent; a missing table
/// (feature never used) is tolerated.
class MigrationV27 {
  final AppDatabase db;
  MigrationV27(this.db);

  Future<void> run(Migrator m) async {
    // Use the GENERATED table name: drift renders `BgMappingSegmentsTable` as
    // `bg_mapping_segments_table` (the class name, snake_cased). A hardcoded
    // 'bg_mapping_segments' made `_tableExists` always false, so the columns
    // were never added while the schema version still advanced — every later
    // insert then failed with "no column named fg_percent".
    final String table = db.bgMappingSegmentsTable.actualTableName;
    if (!await _tableExists(table)) return;
    await _addColumnIfMissing(m, table, db.bgMappingSegmentsTable.fgPercent);
    await _addColumnIfMissing(m, table, db.bgMappingSegmentsTable.bgPercent);
  }

  Future<void> _addColumnIfMissing(
    Migrator m,
    String table,
    GeneratedColumn<Object> column,
  ) async {
    if (await _columnExists(table, column.name)) return;
    _log.i('MigrationV27: adding $table.${column.name}');
    try {
      await m.addColumn(db.bgMappingSegmentsTable, column);
    } catch (e) {
      _log.w('MigrationV27: add ${column.name} failed: $e');
    }
  }

  Future<bool> _tableExists(String name) async {
    final rows = await db.customSelect(
      'SELECT name FROM sqlite_master WHERE type = ? AND name = ?',
      variables: <Variable>[
        Variable.withString('table'),
        Variable.withString(name),
      ],
    ).get();
    return rows.isNotEmpty;
  }

  Future<bool> _columnExists(String table, String column) async {
    try {
      final rows = await db.customSelect('PRAGMA table_info($table)').get();
      for (final row in rows) {
        if (row.read<String>('name') == column) return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}

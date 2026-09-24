import 'package:drift/drift.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/utils/logger.dart';

final _log = AreaKeyLog(LogKeys.legacyDb);

/// Schema v30: repair `bg_mapping_segments.fg_percent` / `bg_percent`.
///
/// The v27 migration hardcoded the table name as `bg_mapping_segments`, but
/// drift's generated name is `bg_mapping_segments_table`. As a result the
/// "table exists?" guard was always false, the two columns were never added,
/// yet the schema version still advanced to 27. Any database upgraded across
/// v27 before this fix is therefore missing both columns and every segment
/// INSERT fails with `no column named fg_percent`.
///
/// v27 is fixed for databases still below 27; this migration repairs the ones
/// that are already stamped past it. Re-entrant: each column is added only when
/// absent, and a missing table is tolerated (feature never used).
class MigrationV30 {
  final AppDatabase db;
  MigrationV30(this.db);

  Future<void> run(Migrator m) async {
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
    _log.i('MigrationV30: adding $table.${column.name}');
    try {
      await m.addColumn(db.bgMappingSegmentsTable, column);
    } catch (e) {
      // Do NOT swallow: this repair exists precisely because a swallowed
      // failure once stamped a version over missing columns. Rethrowing rolls
      // the migration back so the next open retries.
      _log.e('MigrationV30: add ${column.name} failed', e);
      rethrow;
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
    } catch (e) {
      // A failed existence probe is an infrastructure failure, not evidence the
      // column is absent; rethrow so the open retries instead of acting on a
      // guess (which would surface as a misleading secondary error).
      _log.e('MigrationV30: PRAGMA table_info probe failed', e);
      rethrow;
    }
  }
}

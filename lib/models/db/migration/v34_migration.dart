import 'package:drift/drift.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/utils/logger.dart';

final _log = AreaKeyLog(LogKeys.legacyDb);

/// Schema v34: per-segment activation for 副音 mapping.
///
/// - `bg_mapping_segments.is_active` (default 1): a disabled segment keeps its
///   data but is invisible to playback/display, so a mapping can be parked
///   without deleting it.
/// - `bg_mapping_segments.active_seq` (default 0): per-foreground activation
///   order. Larger = activated later; where active segments overlap the largest
///   sequence wins (last-fired-wins), mirroring the WebDAV default-name lit
///   order. Existing rows are backfilled with their id so their current
///   relative order is preserved.
///
/// Re-entrant: each column is added only when absent; a missing table (feature
/// never used) is tolerated.
class MigrationV34 {
  final AppDatabase db;
  MigrationV34(this.db);

  Future<void> run(Migrator m) async {
    final String table = db.bgMappingSegmentsTable.actualTableName;
    if (!await _tableExists(table)) return;
    await _addColumnIfMissing(m, table, db.bgMappingSegmentsTable.isActive);
    await _addColumnIfMissing(m, table, db.bgMappingSegmentsTable.activeSeq);
    await _backfillSeq(table);
  }

  /// Existing rows predate activation: seeding `active_seq = id` keeps their
  /// relative order stable (the id order already matches the insertion order
  /// the user saw).
  Future<void> _backfillSeq(String table) async {
    final hasSeq = await _columnExists(table, 'active_seq');
    if (!hasSeq) return;
    try {
      await db.customStatement(
        'UPDATE $table SET active_seq = id WHERE active_seq = 0',
      );
    } catch (e) {
      // Do NOT swallow: an un-backfilled active_seq silently changes the
      // activation order while the version advances. Rethrowing rolls the
      // migration back so the next open retries.
      _log.e('MigrationV34: backfill active_seq failed', e);
      rethrow;
    }
  }

  Future<void> _addColumnIfMissing(
    Migrator m,
    String table,
    GeneratedColumn<Object> column,
  ) async {
    if (await _columnExists(table, column.name)) return;
    _log.i('MigrationV34: adding $table.${column.name}');
    try {
      await m.addColumn(db.bgMappingSegmentsTable, column);
    } catch (e) {
      // Do NOT swallow: a missing column while the version advances would break
      // the activation read/write paths. Rethrowing rolls the migration back so
      // the next open retries.
      _log.e('MigrationV34: add ${column.name} failed', e);
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
      _log.e('MigrationV34: PRAGMA table_info probe failed', e);
      rethrow;
    }
  }
}

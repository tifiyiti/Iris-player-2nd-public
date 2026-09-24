import 'package:drift/drift.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/utils/logger.dart';

final _log = AreaKeyLog(LogKeys.legacyDb);

/// Schema v32: per-segment label colour for 副音 mapping segments.
///
/// - `bg_mapping_segments.color_argb` (NULL-able): the ARGB colour painted on
///   the foreground axis for this segment. NULL = no explicit choice; the UI
///   derives a stable colour and assigns a random palette colour on first save.
///   Purely cosmetic — it never participates in playback, overlap validation or
///   resolution, so every existing row stays valid and unchanged.
///
/// Re-entrant: the column is created only when absent; a missing table (feature
/// never used) is tolerated.
class MigrationV32 {
  final AppDatabase db;
  MigrationV32(this.db);

  Future<void> run(Migrator m) async {
    final String table = db.bgMappingSegmentsTable.actualTableName;
    if (!await _tableExists(table)) return;
    await _addColumnIfMissing(m, table, db.bgMappingSegmentsTable.colorArgb);
  }

  Future<void> _addColumnIfMissing(
    Migrator m,
    String table,
    GeneratedColumn<Object> column,
  ) async {
    if (await _columnExists(table, column.name)) return;
    _log.i('MigrationV32: adding $table.${column.name}');
    try {
      await m.addColumn(db.bgMappingSegmentsTable, column);
    } catch (e) {
      // Do NOT swallow: a missing column while the version advances would break
      // the segment read/write paths. Rethrowing rolls the migration back so
      // the next open retries.
      _log.e('MigrationV32: add ${column.name} failed', e);
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
      _log.e('MigrationV32: PRAGMA table_info probe failed', e);
      rethrow;
    }
  }
}

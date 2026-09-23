import 'package:drift/drift.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/utils/logger.dart';

final _log = AreaKeyLog(LogKeys.legacyDb);

/// Schema v26: 副音 playback foreground-mapping timelines.
///
/// - `bg_mappings`: one timeline parent per foreground media
///   (storage_id + canonical path, UNIQUE).
/// - `bg_mapping_segments`: ordered non-overlapping segments of that timeline
///   (playMedia | silence; absolute ms + normalized fractions).
///
/// Re-entrant: every step checks sqlite_master before creating; missing
/// tables (feature never used / legacy era) are tolerated.
class MigrationV26 {
  final AppDatabase db;
  MigrationV26(this.db);

  Future<void> run(Migrator m) async {
    await _createIfMissing(db.bgMappingsTable, m);
    await _createIfMissing(db.bgMappingSegmentsTable, m);
  }

  Future<void> _createIfMissing(TableInfo<Table, dynamic> table, Migrator m) async {
    final String name = table.actualTableName;
    if (await _tableExists(name)) return;
    _log.i('MigrationV26: creating $name');
    try {
      await m.createTable(table);
    } catch (e) {
      _log.w('MigrationV26: create $name failed: $e');
    }
  }

  Future<bool> _tableExists(String name) async {
    try {
      final rows = await db.customSelect(
        'SELECT name FROM sqlite_master WHERE type = ? AND name = ?',
        variables: <Variable>[
          Variable.withString('table'),
          Variable.withString(name),
        ],
      ).get();
      return rows.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}

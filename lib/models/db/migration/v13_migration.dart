import 'package:drift/drift.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/utils/logger.dart';

final _log = AreaKeyLog(LogKeys.legacyDb);

/// Schema v13: introduce the tag_play subsystem.
///
/// Four ADDITIVE tables; no existing table or column is touched:
///  - video_tags           : tag definitions (+ retention policy)
///  - video_tag_members    : (tag, storageId, canonical path) + addedAt
///  - video_tag_view_state : per-tag global play-view spec + bookmark
///  - video_tag_pin_preset : named snapshots of the pin order
///
/// Each creation is existence-guarded so the migration is safely re-entrant.
class MigrationV13 {
  final AppDatabase db;

  MigrationV13(this.db);

  Future<void> run(Migrator m) async {
    await _createIfMissing(db.videoTagsTable, m);
    await _createIfMissing(db.videoTagMembersTable, m);
    await _createIfMissing(db.videoTagViewStatesTable, m);
    await _createIfMissing(db.videoTagPinPresetsTable, m);
  }

  Future<void> _createIfMissing(dynamic table, Migrator m) async {
    final String name = table.actualTableName as String;
    if (!await _tableExists(name)) {
      _log.i('MigrationV13: creating $name');
      await m.createTable(table as TableInfo<Table, dynamic>);
    }
  }

  Future<bool> _tableExists(String name) async {
    final rows = await db.customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      variables: <Variable>[Variable.withString(name)],
    ).get();
    return rows.isNotEmpty;
  }
}

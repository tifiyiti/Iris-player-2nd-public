import 'package:drift/drift.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/utils/logger.dart';

final _log = AreaKeyLog(LogKeys.legacyDb);

/// Schema v37: stable volume identity for local storages.
///
/// Adds `storages_table.volume_id` — the drive-letter-independent key (Windows
/// volume GUID / Android volume UUID) used to match a re-mounted disk to its
/// existing entry so its media-node tree is reused instead of re-scanned under
/// a new letter.
///
/// Existing rows are backfilled lazily at enumeration: a Drift migration cannot
/// reliably resolve platform volume identities, and NULL simply means "not yet
/// resolved" — the reconciler fills it on the next mount.
class MigrationV37 {
  final AppDatabase db;

  MigrationV37(this.db);

  Future<void> run(Migrator m) async {
    final cols = await _columnNames('storages_table');
    if (cols == null) return;
    if (!cols.contains('volume_id')) {
      _log.i('MigrationV37: adding storages_table.volume_id');
      await m.addColumn(db.storagesTable, db.storagesTable.volumeId);
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

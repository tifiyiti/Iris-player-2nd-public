import 'package:drift/drift.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/tables/storage_table.dart';
import 'package:iris/utils/logger.dart';

part 'storage_dao.g.dart';

final _log = AreaKeyLog(LogKeys.legacyDb);

@DriftAccessor(tables: [StoragesTable])
class StorageDao extends DatabaseAccessor<AppDatabase> with _$StorageDaoMixin {
  StorageDao(super.db);

  Future<List<StoragesTableData>> getAll() {
    return select(storagesTable).get();
  }

  Future<void> insert(StoragesTableCompanion entry) {
    return into(storagesTable).insert(entry);
  }

  Future<void> upsert(StoragesTableCompanion entry) {
    return into(storagesTable).insertOnConflictUpdate(entry);
  }

  Future<void> deleteById(String id) {
    return (delete(storagesTable)..where((t) => t.id.equals(id))).go();
  }

  /// Full replace, optionally sparing [preserveIds].
  ///
  /// Preserved ids are neither deleted nor re-inserted, so their rows stay
  /// byte-for-byte as they are. Used to protect entries whose password could
  /// not be decrypted: the in-memory placeholder must not overwrite the stored
  /// cipher/connection fields.
  Future<void> replaceAll(
    List<StoragesTableCompanion> entries, {
    Set<String> preserveIds = const <String>{},
  }) {
    return transaction(() async {
      if (entries.isEmpty && preserveIds.isEmpty) {
        // Tripwire: a full replace with nothing to insert clears the table.
        // Intended only for a user-initiated "no storages left" state; anything
        // else is the storage-loss bug in disguise.
        final rows = await select(storagesTable).get();
        if (rows.isNotEmpty) {
          _log.w('storages_table: replaceAll got an EMPTY list but the table '
              'holds ${rows.length} row(s) — clearing them all');
        }
      }
      if (preserveIds.isEmpty) {
        await delete(storagesTable).go();
      } else {
        await (delete(storagesTable)
              ..where((t) => t.id.isNotIn(preserveIds)))
            .go();
      }
      for (final e in entries) {
        await insert(e);
      }
    });
  }
}

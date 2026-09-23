import 'package:drift/drift.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/tables/storage_table.dart';
import 'package:iris/utils/logger.dart';

part 'favorites_dao.g.dart';

final _log = AreaKeyLog(LogKeys.legacyDb);

@DriftAccessor(tables: [FavoritesTable])
class FavoritesDao extends DatabaseAccessor<AppDatabase> with _$FavoritesDaoMixin {
  FavoritesDao(super.db);

  Future<List<FavoritesTableData>> getAll() {
    return select(favoritesTable).get();
  }

  Future<void> upsert(FavoritesTableCompanion entry) {
    return into(favoritesTable).insertOnConflictUpdate(entry);
  }

  Future<void> deleteByKey(String storageId, String pathJson) {
    return (delete(favoritesTable)
          ..where((t) => t.storageId.equals(storageId) & t.path.equals(pathJson)))
        .go();
  }

  Future<void> replaceAll(List<FavoritesTableCompanion> entries) async {
    if (entries.isEmpty) {
      // Tripwire, same shape as StorageDao.replaceAll: a full replace with
      // nothing to insert clears the table.
      final rows = await select(favoritesTable).get();
      if (rows.isNotEmpty) {
        _log.w('favorites_table: replaceAll got an EMPTY list but the table '
            'holds ${rows.length} row(s) — clearing them all');
      }
    }
    return batch((b) {
      b.deleteAll(favoritesTable);
      b.insertAllOnConflictUpdate(favoritesTable, entries);
    });
  }
}

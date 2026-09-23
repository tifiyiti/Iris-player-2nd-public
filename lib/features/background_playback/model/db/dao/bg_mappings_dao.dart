import 'package:drift/drift.dart';
import 'package:iris/features/background_playback/model/db/tables/bg_mappings_table.dart';
import 'package:iris/models/db/app_database.dart';

part 'bg_mappings_dao.g.dart';

@DriftAccessor(tables: [BgMappingsTable])
class BgMappingsDao extends DatabaseAccessor<AppDatabase>
    with _$BgMappingsDaoMixin {
  BgMappingsDao(super.db);

  Future<BgMappingsTableData?> getByFg({
    required String storageId,
    required String path,
  }) {
    return (select(bgMappingsTable)
          ..where((t) =>
              t.storageId.equals(storageId) & t.path.equals(path))
          ..limit(1))
        .getSingleOrNull();
  }

  /// Every saved mapping timeline, newest edit first — the manager's Level-1
  /// source.
  Future<List<BgMappingsTableData>> getAll() {
    return (select(bgMappingsTable)
          ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
        .get();
  }

  /// Reactive variant of [getAll] (manager list refresh).
  Stream<List<BgMappingsTableData>> watchAll() {
    return (select(bgMappingsTable)
          ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
        .watch();
  }

  Future<int> insertRow({
    required String storageId,
    required String path,
    int? mediaId,
    int? fgTotalMs,
  }) {
    return into(bgMappingsTable).insert(
      BgMappingsTableCompanion.insert(
        storageId: storageId,
        path: path,
        mediaId: Value(mediaId),
        fgTotalMs: Value(fgTotalMs),
      ),
    );
  }

  Future<void> updateTotalAndMedia(
    int id, {
    int? mediaId,
    int? fgTotalMs,
  }) async {
    await (update(bgMappingsTable)..where((t) => t.id.equals(id))).write(
      BgMappingsTableCompanion(
        mediaId: Value(mediaId),
        fgTotalMs: Value(fgTotalMs),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> deleteRow(int id) async {
    await (delete(bgMappingsTable)..where((t) => t.id.equals(id))).go();
  }
}

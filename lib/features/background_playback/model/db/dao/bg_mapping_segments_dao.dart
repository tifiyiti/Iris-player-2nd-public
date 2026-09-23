import 'package:drift/drift.dart';
import 'package:iris/features/background_playback/model/db/tables/bg_mapping_segments_table.dart';
import 'package:iris/models/db/app_database.dart';

part 'bg_mapping_segments_dao.g.dart';

@DriftAccessor(tables: [BgMappingSegmentsTable])
class BgMappingSegmentsDao extends DatabaseAccessor<AppDatabase>
    with _$BgMappingSegmentsDaoMixin {
  BgMappingSegmentsDao(super.db);

  Future<List<BgMappingSegmentsTableData>> getForMapping(int mappingId) {
    return (select(bgMappingSegmentsTable)
          ..where((t) => t.mappingId.equals(mappingId))
          ..orderBy([(t) => OrderingTerm.asc(t.fgStartMs)]))
        .get();
  }

  /// Every segment of every timeline in ONE query, ordered so the repository
  /// can group by [mappingId] without an N+1 round trip (manager list).
  Future<List<BgMappingSegmentsTableData>> getAll() {
    return (select(bgMappingSegmentsTable)
          ..orderBy([
            (t) => OrderingTerm.asc(t.mappingId),
            (t) => OrderingTerm.asc(t.fgStartMs),
          ]))
        .get();
  }

  Future<int> insertSegment(BgMappingSegmentsTableCompanion entry) {
    return into(bgMappingSegmentsTable).insert(entry);
  }

  Future<void> deleteForMapping(int mappingId) async {
    await (delete(bgMappingSegmentsTable)
          ..where((t) => t.mappingId.equals(mappingId)))
        .go();
  }

  Future<void> deleteSegment(int id) async {
    await (delete(bgMappingSegmentsTable)..where((t) => t.id.equals(id)))
        .go();
  }
}

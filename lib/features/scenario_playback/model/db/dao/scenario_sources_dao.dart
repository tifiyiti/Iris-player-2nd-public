import 'package:drift/drift.dart';
import 'package:iris/features/scenario_playback/model/db/adapters/scenario_source_adapter.dart';
import 'package:iris/features/scenario_playback/model/db/tables/scenario_sources_table.dart';
import 'package:iris/features/scenario_playback/model/domain/scenario_source.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/utils/path_prefix_remap.dart';

part 'scenario_sources_dao.g.dart';

@DriftAccessor(tables: [ScenarioSourcesTable])
class ScenarioSourcesDao extends DatabaseAccessor<AppDatabase>
    with _$ScenarioSourcesDaoMixin {
  ScenarioSourcesDao(super.db);

  Future<List<ScenarioSource>> getByScenario(String scenarioId) async {
    final rows = await (select(scenarioSourcesTable)
          ..where((t) => t.scenarioId.equals(scenarioId))
          ..orderBy([
            (t) => OrderingTerm(expression: t.sortOrder, mode: OrderingMode.asc),
            (t) => OrderingTerm(expression: t.id, mode: OrderingMode.asc),
          ]))
        .get();
    return rows.map(ScenarioSourceAdapter.fromDb).toList();
  }

  Future<List<ScenarioSource>> getAll() async {
    final rows = await (select(scenarioSourcesTable)
          ..orderBy([(t) => OrderingTerm(expression: t.id, mode: OrderingMode.asc)]))
        .get();
    return rows.map(ScenarioSourceAdapter.fromDb).toList();
  }

  Future<int> nextSortOrder(String scenarioId) async {
    final row = await (select(scenarioSourcesTable)
          ..where((t) => t.scenarioId.equals(scenarioId))
          ..orderBy([(t) => OrderingTerm(expression: t.sortOrder, mode: OrderingMode.desc)])
          ..limit(1))
        .getSingleOrNull();
    return row == null ? 0 : row.sortOrder + 1;
  }

  Future<void> upsert(ScenarioSource source) {
    return into(scenarioSourcesTable).insertOnConflictUpdate(
      source.toCompanion(),
    );
  }

  Future<void> deleteSource(int sourceId) {
    return (delete(scenarioSourcesTable)..where((t) => t.id.equals(sourceId))).go();
  }

  Future<void> deleteByScenario(String scenarioId) {
    return (delete(scenarioSourcesTable)..where((t) => t.scenarioId.equals(scenarioId))).go();
  }

  /// Rewrites the leading [oldBase] of every source path for [storageId] to
  /// [newBase] (drive-letter reassignment). Whole-storage rows (`path == ''`)
  /// are untouched.
  Future<int> remapPathPrefix({
    required String storageId,
    required String oldBase,
    required String newBase,
  }) {
    final query = buildPathPrefixRemap(
      table: 'scenario_sources',
      keyColumn: 'storage_id',
      keyValue: storageId,
      oldBase: oldBase,
      newBase: newBase,
    );
    return customUpdate(
      query.sql,
      variables: query.variables,
      updates: {scenarioSourcesTable},
    );
  }
}

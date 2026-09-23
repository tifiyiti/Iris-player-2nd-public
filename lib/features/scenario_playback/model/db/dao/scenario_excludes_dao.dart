import 'package:drift/drift.dart';
import 'package:iris/features/scenario_playback/model/db/adapters/scenario_exclude_rule_adapter.dart';
import 'package:iris/features/scenario_playback/model/db/tables/scenario_excludes_table.dart';
import 'package:iris/features/scenario_playback/model/domain/scenario_exclude_rule.dart';
import 'package:iris/features/scenario_playback/model/enum/exclude_scope.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/utils/path_conv.dart';
import 'package:iris/utils/path_prefix_remap.dart';

part 'scenario_excludes_dao.g.dart';

@DriftAccessor(tables: [ScenarioExcludesTable])
class ScenarioExcludesDao extends DatabaseAccessor<AppDatabase>
    with _$ScenarioExcludesDaoMixin {
  ScenarioExcludesDao(super.db);

  Future<List<ScenarioExcludeRule>> getByScenario(String scenarioId) async {
    final rows = await (select(scenarioExcludesTable)
          ..where((t) => t.scenarioId.equals(scenarioId))
          ..orderBy([(t) => OrderingTerm(expression: t.id, mode: OrderingMode.asc)]))
        .get();
    return rows.map(ScenarioExcludeRuleAdapter.fromDb).toList();
  }

  /// Finds a logically-equal rule (F1): same 6-tuple with NULL-equality on
  /// sourceId. [lifetime] is NOT part of the logical key.
  Future<ScenarioExcludeRule?> findLogical({
    required String scenarioId,
    required ExcludeScope scope,
    required int? sourceId,
    required String kind,
    required String storageId,
    required String path,
  }) async {
    // Canonicalize the input so callers with different slash conventions
    // (rooted `/storage/...`, canonical `storage/...`) match the same rows.
    final canonical = canonicalDbPath(path);
    final rows = await (select(scenarioExcludesTable)
          ..where((t) =>
              t.scenarioId.equals(scenarioId) &
              t.scope.equals(scope.name) &
              (sourceId == null ? t.sourceId.isNull() : t.sourceId.equals(sourceId)) &
              t.kind.equals(kind) &
              t.storageId.equals(storageId) &
              t.path.equals(canonical))
          ..limit(1))
        .get();
    return rows.isEmpty ? null : ScenarioExcludeRuleAdapter.fromDb(rows.first);
  }

  Future<void> deleteRule(int ruleId) {
    return (delete(scenarioExcludesTable)..where((t) => t.id.equals(ruleId))).go();
  }

  Future<void> upsert(ScenarioExcludeRule rule) {
    return into(scenarioExcludesTable).insertOnConflictUpdate(
      rule.toCompanion(),
    );
  }

  Future<void> deleteByScenario(String scenarioId) {
    return (delete(scenarioExcludesTable)
          ..where((t) => t.scenarioId.equals(scenarioId)))
        .go();
  }

  Future<void> deleteTemporary(String scenarioId) {
    return (delete(scenarioExcludesTable)
          ..where((t) => t.scenarioId.equals(scenarioId) & t.lifetime.equals('temporary')))
        .go();
  }

  /// Rewrites the leading [oldBase] of every exclude rule path for [storageId]
  /// to [newBase] (drive-letter reassignment).
  Future<int> remapPathPrefix({
    required String storageId,
    required String oldBase,
    required String newBase,
  }) {
    final query = buildPathPrefixRemap(
      table: 'scenario_excludes',
      keyColumn: 'storage_id',
      keyValue: storageId,
      oldBase: oldBase,
      newBase: newBase,
    );
    return customUpdate(
      query.sql,
      variables: query.variables,
      updates: {scenarioExcludesTable},
    );
  }
}

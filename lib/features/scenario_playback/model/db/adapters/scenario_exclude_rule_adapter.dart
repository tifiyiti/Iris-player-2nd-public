import 'package:drift/drift.dart';
import 'package:iris/features/scenario_playback/model/domain/scenario_exclude_rule.dart';
import 'package:iris/features/scenario_playback/model/enum/exclude_lifetime.dart';
import 'package:iris/features/scenario_playback/model/enum/exclude_scope.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/utils/path_conv.dart';

extension ScenarioExcludeRuleAdapter on ScenarioExcludeRule {
  static ScenarioExcludeRule fromDb(ScenarioExcludesTableData row) {
    return ScenarioExcludeRule(
      id: row.id,
      scenarioId: row.scenarioId,
      scope: row.scope ?? ExcludeScope.scenario,
      lifetime: row.lifetime ?? ExcludeLifetime.persistent,
      sourceId: row.sourceId,
      kind: row.kind,
      storageId: row.storageId,
      path: row.path,
      recursive: row.recursive,
      createdAt: row.createdAt,
    );
  }

  ScenarioExcludesTableCompanion toCompanion() {
    return ScenarioExcludesTableCompanion(
      id: id == 0 ? const Value.absent() : Value(id),
      scenarioId: Value(scenarioId),
      scope: Value(scope),
      lifetime: Value(lifetime),
      sourceId: Value(sourceId),
      kind: Value(kind),
      storageId: Value(storageId),
      // path: Value(path),  // legacy: caller-slash-dependent
      path: Value(canonicalDbPath(path)), // unified canonical form
      recursive: Value(recursive),
      createdAt: Value(createdAt),
    );
  }
}

import 'package:drift/drift.dart';
import 'package:iris/features/scenario_playback/model/domain/scenario_source.dart';
import 'package:iris/features/scenario_playback/model/enum/scenario_source_kind.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/utils/path_conv.dart';

extension ScenarioSourceAdapter on ScenarioSource {
  static ScenarioSource fromDb(ScenarioSourcesTableData row) {
    return ScenarioSource(
      id: row.id,
      scenarioId: row.scenarioId,
      storageId: row.storageId,
      path: row.path,
      recursive: row.recursive,
      sourceKind: row.sourceKind ?? ScenarioSourceKind.folder,
      sortOrder: row.sortOrder,
      createdAt: row.createdAt,
    );
  }

  ScenarioSourcesTableCompanion toCompanion() {
    return ScenarioSourcesTableCompanion(
      id: id == 0 ? const Value.absent() : Value(id),
      scenarioId: Value(scenarioId),
      storageId: Value(storageId),
      // path: Value(path),  // legacy: caller-slash-dependent
      path: Value(canonicalDbPath(path)), // unified canonical form
      recursive: Value(recursive),
      sourceKind: Value(sourceKind),
      sortOrder: Value(sortOrder),
      createdAt: Value(createdAt),
    );
  }
}

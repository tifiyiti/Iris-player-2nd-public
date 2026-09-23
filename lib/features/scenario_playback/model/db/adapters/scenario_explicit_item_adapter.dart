import 'package:drift/drift.dart';
import 'package:iris/features/scenario_playback/model/domain/scenario_explicit_item.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/utils/path_conv.dart';

extension ScenarioExplicitItemAdapter on ScenarioExplicitItem {
  static ScenarioExplicitItem fromDb(ScenarioExplicitItemsTableData row) {
    return ScenarioExplicitItem(
      id: row.id,
      scenarioId: row.scenarioId,
      batchId: row.batchId,
      storageId: row.storageId,
      path: row.path,
      mediaId: row.mediaId,
      addOrder: row.addOrder,
      uiSortKey: row.uiSortKey,
      createdAt: row.createdAt,
    );
  }

  ScenarioExplicitItemsTableCompanion toCompanion() {
    return ScenarioExplicitItemsTableCompanion(
      id: id == 0 ? const Value.absent() : Value(id),
      scenarioId: Value(scenarioId),
      batchId: Value(batchId),
      storageId: Value(storageId),
      // path: Value(path),  // legacy: caller-slash-dependent
      path: Value(canonicalDbPath(path)), // unified canonical form
      mediaId: Value(mediaId),
      addOrder: Value(addOrder),
      uiSortKey: Value(uiSortKey),
      createdAt: Value(createdAt),
    );
  }
}

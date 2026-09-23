import 'package:drift/drift.dart';
import 'package:iris/features/virtual_media/model/db/tables/virtual_media_tables.dart';
import 'package:iris/models/db/app_database.dart';

part 'virtual_media_progress_dao.g.dart';

/// Per-scenario/tag virtual-media progress (v21 `vm_progress`).
///
/// PK `(scenario_id, tag_id, scope_key)` — one row per virtual item per
/// scenario/tag context. Cleared on `stop` and on rule structural edits.
@DriftAccessor(tables: [VmProgressTable])
class VirtualMediaProgressDao extends DatabaseAccessor<AppDatabase>
    with _$VirtualMediaProgressDaoMixin {
  VirtualMediaProgressDao(super.db);

  Future<VmProgressTableData?> get(
      String scenarioId, String tagId, String scopeKey) {
    return (select(vmProgressTable)
          ..where((t) =>
              t.scenarioId.equals(scenarioId) &
              t.tagId.equals(tagId) &
              t.scopeKey.equals(scopeKey)))
        .getSingleOrNull();
  }

  Future<void> save({
    required String scenarioId,
    required String tagId,
    required String ruleId,
    required String scopeKey,
    required String segmentKey,
    required int localPositionMs,
  }) {
    return into(vmProgressTable).insertOnConflictUpdate(
      VmProgressTableCompanion.insert(
        scenarioId: scenarioId,
        ruleId: ruleId,
        scopeKey: scopeKey,
        tagId: Value(tagId),
        segmentKey: Value(segmentKey),
        localPositionMs: Value(localPositionMs),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<int> deleteForScope(
      String scenarioId, String tagId, String scopeKey) {
    return (delete(vmProgressTable)
          ..where((t) =>
              t.scenarioId.equals(scenarioId) &
              t.tagId.equals(tagId) &
              t.scopeKey.equals(scopeKey)))
        .go();
  }

  Future<int> deleteForRule(String ruleId) {
    return (delete(vmProgressTable)
          ..where((t) => t.ruleId.equals(ruleId)))
        .go();
  }

  Future<int> deleteForScopeKey(String scopeKey) {
    return (delete(vmProgressTable)
          ..where((t) => t.scopeKey.equals(scopeKey)))
        .go();
  }

  Future<int> clearAll() => delete(vmProgressTable).go();
}

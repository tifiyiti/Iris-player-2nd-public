import 'package:drift/drift.dart';
import 'package:iris/features/scenario_playback/model/db/adapters/scenario_state_adapter.dart';
import 'package:iris/features/scenario_playback/model/db/tables/scenario_states_table.dart';
import 'package:iris/features/scenario_playback/model/domain/scenario_state.dart';
import 'package:iris/models/db/app_database.dart';

part 'scenario_states_dao.g.dart';

@DriftAccessor(tables: [ScenarioStatesTable])
class ScenarioStatesDao extends DatabaseAccessor<AppDatabase>
    with _$ScenarioStatesDaoMixin {
  ScenarioStatesDao(super.db);

  Future<ScenarioState?> getByScenario(String scenarioId) async {
    final row = await (select(scenarioStatesTable)
          ..where((t) => t.scenarioId.equals(scenarioId))
          ..limit(1))
        .getSingleOrNull();
    return row == null ? null : ScenarioStateAdapter.fromDb(row);
  }

  Future<void> upsert(ScenarioState state) {
    return into(scenarioStatesTable).insertOnConflictUpdate(
      state.toCompanion(),
    );
  }

  Future<void> deleteByScenario(String scenarioId) {
    return (delete(scenarioStatesTable)
          ..where((t) => t.scenarioId.equals(scenarioId)))
        .go();
  }
}

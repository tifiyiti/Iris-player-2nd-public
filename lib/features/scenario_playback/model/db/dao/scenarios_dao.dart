import 'package:drift/drift.dart';
import 'package:iris/features/scenario_playback/model/db/adapters/scenario_adapter.dart';
import 'package:iris/features/scenario_playback/model/db/tables/scenarios_table.dart';
import 'package:iris/features/scenario_playback/model/domain/scenario.dart';
import 'package:iris/features/scenario_playback/model/enum/scenario_kind.dart';
import 'package:iris/models/db/app_database.dart';

part 'scenarios_dao.g.dart';

@DriftAccessor(tables: [ScenariosTable])
class ScenariosDao extends DatabaseAccessor<AppDatabase> with _$ScenariosDaoMixin {
  ScenariosDao(super.db);

  Future<List<Scenario>> getAll() async {
    final rows = await (select(scenariosTable)
          ..orderBy([(t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.asc)]))
        .get();
    return rows.map(ScenarioAdapter.fromDb).toList();
  }

  Future<Scenario?> getById(String scenarioId) async {
    final row = await (select(scenariosTable)
          ..where((t) => t.id.equals(scenarioId))
          ..limit(1))
        .getSingleOrNull();
    return row == null ? null : ScenarioAdapter.fromDb(row);
  }

  Future<Scenario?> getByType(ScenarioKind kind) async {
    final row = await (select(scenariosTable)
          ..where((t) => t.type.equals(kind.name))
          ..limit(1))
        .getSingleOrNull();
    return row == null ? null : ScenarioAdapter.fromDb(row);
  }

  Future<void> upsert(Scenario scenario) {
    return into(scenariosTable).insertOnConflictUpdate(
      scenario.toCompanion(),
    );
  }

  Future<void> deleteScenario(String scenarioId) {
    return (delete(scenariosTable)..where((t) => t.id.equals(scenarioId))).go();
  }
}

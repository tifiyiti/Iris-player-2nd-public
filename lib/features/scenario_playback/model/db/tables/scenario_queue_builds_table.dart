import 'package:drift/drift.dart';

/// Per-generation metadata for the scenario derived queue index (schema v39).
///
/// One row per (scenario, build). Carries the BASE file count (= the queue's
/// index space / `totalItems`) independently of how many visible rows the
/// generation has, so a paged read never has to derive it from the rows.
class ScenarioQueueBuildsTable extends Table {
  @override
  String get tableName => 'scenario_queue_builds';

  TextColumn get scenarioId => text()();

  IntColumn get buildId => integer()();

  /// Accepted effective-stream item count = the base rank space size.
  IntColumn get baseCount => integer()();

  /// Number of visible list rows (file rows + group rows).
  IntColumn get entryCount => integer()();

  DateTimeColumn get builtAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {scenarioId, buildId};
}

import 'package:drift/drift.dart';

/// PLAYBACK STATE of a Scenario (D1/D4) — the runtime half, persisted with the
/// scenario so playing it again resumes where it left off.
///
/// Definition config lives on the scenario table, not here.
class ScenarioStatesTable extends Table {
  @override
  String get tableName => 'scenario_state';

  TextColumn get scenarioId => text()();

  /// JSON of PlaybackOccurrenceId (D4). Opaque to SQL.
  TextColumn get currentPlaybackOccurrence => text().nullable()();

  /// Ordering hint of the current item in the current resolve order.
  IntColumn get currentVirtualPos => integer().nullable()();

  /// Deterministic shuffle seed. Never store the whole shuffled array.
  IntColumn get shuffleSeed => integer().nullable()();

  IntColumn get shuffleVersion => integer().withDefault(const Constant(0))();

  IntColumn get shuffleItemCount => integer().withDefault(const Constant(0))();

  /// Sync-back target (E2/F2). Null ⇒ Sync disabled.
  TextColumn get originScenarioId => text().nullable()();

  DateTimeColumn get importedAt => dateTime().nullable()();

  IntColumn get importVersion => integer().nullable()();

  DateTimeColumn get lastActiveAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {scenarioId};
}

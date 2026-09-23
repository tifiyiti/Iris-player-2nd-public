import 'package:drift/drift.dart';
import 'package:iris/models/db/app_database.dart';

/// Schema v7: scenario-driven playback tables (v9 layout).
///
/// The table objects now reflect the final v9 shape, so a pre-v7 database is
/// created directly with the current scenario schema; later v8/v9 migrations
/// become guarded no-ops on that path.
class MigrationV7 {
  final AppDatabase db;

  MigrationV7(this.db);

  Future<void> run(Migrator m) async {
    await db.transaction(() async {
      await m.createTable(db.scenariosTable);
      await m.createTable(db.scenarioSourcesTable);
      await m.createTable(db.scenarioExplicitItemsTable);
      await m.createTable(db.scenarioExcludesTable);
      await m.createTable(db.scenarioStatesTable);
    });
  }
}

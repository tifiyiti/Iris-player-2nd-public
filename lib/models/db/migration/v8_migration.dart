import 'package:drift/drift.dart';
import 'package:iris/models/db/app_database.dart';

/// Schema v8: rename PlaybackContext → PlaybackScenario.
///
/// Renames the 5 scenario-owned tables and their `context_id` columns to the
/// new naming. The global `media_playback_progress` table is unchanged.
///
/// Renames are conditional so the migration is safe for every upgrade path:
/// - a fresh database is created with the new names directly (no-op here)
/// - a v6 database gets the new names via MigrationV7 (no-op here)
/// - a pre-rename v7 database still holds the old table/column names (renamed)
class MigrationV8 {
  final AppDatabase db;

  MigrationV8(this.db);

  Future<void> run(Migrator m) async {
    await db.transaction(() async {
      const tableRenames = <String, String>{
        'playback_contexts': 'playback_scenarios',
        'context_sources': 'scenario_sources',
        'context_explicit_includes': 'scenario_explicit_includes',
        'context_exclude_rules': 'scenario_exclude_rules',
        'playback_context_states': 'playback_scenario_states',
      };

      for (final entry in tableRenames.entries) {
        if (await _tableExists(entry.key)) {
          await db.customStatement(
            'ALTER TABLE `${entry.key}` RENAME TO `${entry.value}`',
          );
        }
      }

      const columnRenames = <String, String>{
        'scenario_sources': 'context_id',
        'scenario_explicit_includes': 'context_id',
        'scenario_exclude_rules': 'context_id',
        'playback_scenario_states': 'context_id',
      };

      for (final entry in columnRenames.entries) {
        if (await _columnExists(entry.key, entry.value)) {
          await db.customStatement(
            'ALTER TABLE `${entry.key}` RENAME COLUMN `${entry.value}` '
            'TO `scenario_id`',
          );
        }
      }
    });
  }

  Future<bool> _tableExists(String name) async {
    final rows = await db.customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      variables: [Variable(name)],
    ).get();
    return rows.isNotEmpty;
  }

  Future<bool> _columnExists(String table, String column) async {
    final rows = await db.customSelect('PRAGMA table_info(`$table`)').get();
    for (final row in rows) {
      if (row.data['name'] == column) return true;
    }
    return false;
  }
}

import 'package:drift/drift.dart';
import 'package:iris/features/media_library/model/enum/basic_enum.dart';
import 'package:iris/features/scenario_playback/model/db/adapters/scenario_adapter.dart';
import 'package:iris/features/scenario_playback/model/db/adapters/scenario_state_adapter.dart';
import 'package:iris/features/scenario_playback/model/domain/playback_occurrence_id.dart';
import 'package:iris/features/scenario_playback/model/domain/scenario.dart';
import 'package:iris/features/scenario_playback/model/domain/scenario_state.dart';
import 'package:iris/features/scenario_playback/model/enum/duplicate_policy.dart';
import 'package:iris/features/scenario_playback/model/enum/exclude_lifetime.dart';
import 'package:iris/features/scenario_playback/model/enum/exclude_rule_kind.dart';
import 'package:iris/features/scenario_playback/model/enum/exclude_scope.dart';
import 'package:iris/features/scenario_playback/model/enum/playback_order.dart';
import 'package:iris/features/scenario_playback/model/enum/scenario_kind.dart';
import 'package:iris/features/scenario_playback/model/enum/scenario_sort_field.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/store/app_state.dart' show Repeat;
import 'package:iris/utils/logger.dart';
final areaKeyLog = AreaKeyLog(LogKeys.legacyDb);

/// Schema v9: two-level Scenario model (SystemPlaying + Saved).
///
/// Applies the v6 plan:
/// - media_nodes gains global playback-progress columns; media_playback_progress
///   is dropped after backfill.
/// - `playback_scenarios → scenario` (rebuild, B1): + type/description/version,
///   config columns JOINed from the old states table (D1), version NULL for the
///   systemPlaying row (E4).
/// - `scenario_sources` += sort_order (A4).
/// - `scenario_explicit_includes → scenario_explicit_items` (rebuild, B1):
///   + batch_id/add_order/ui_sort_key.
/// - `scenario_exclude_rules → scenario_excludes` (rebuild, B1 + F1): + scope/
///   lifetime/source_id, NO unique constraint.
/// - `playback_scenario_states → scenario_state` (rebuild, D4/E2):
///   current_playback_occurrence JSON + current_virtual_pos + origin_scenario_id.
///
/// All rebuilds follow the v4 pattern (rename → create → copy → drop) because
/// SQLite cannot alter enum columns in place.
class MigrationV9 {
  final AppDatabase db;

  MigrationV9(this.db);

  Future<void> run(Migrator m) async {
    await db.transaction(() async {
      await _migrateMediaNodes(m);
      await _migrateScenarios(m);
      await _migrateSources(m);
      await _migrateExplicitItems(m);
      await _migrateExcludes(m);
      await _migrateStates(m);
      await _ensureSystemPlaying();
    });
  }

  // ── 1. media_nodes progress columns + drop media_playback_progress ──

  Future<void> _migrateMediaNodes(Migrator m) async {
    if (!await _columnExists('media_nodes', 'playback_position_ms')) {
      await m.addColumn(db.mediaNodesTable, db.mediaNodesTable.playbackPositionMs);
    }
    if (!await _columnExists('media_nodes', 'playback_completed')) {
      await m.addColumn(db.mediaNodesTable, db.mediaNodesTable.playbackCompleted);
    }
    if (!await _columnExists('media_nodes', 'last_played_at')) {
      await m.addColumn(db.mediaNodesTable, db.mediaNodesTable.lastPlayedAt);
    }
    if (!await _columnExists('media_nodes', 'play_count')) {
      await m.addColumn(db.mediaNodesTable, db.mediaNodesTable.playCount);
    }

    if (await _tableExists('media_playback_progress')) {
      await db.customStatement('''
        UPDATE media_nodes
        SET playback_position_ms = (
              SELECT p.position_ms FROM media_playback_progress p
              WHERE p.storage_id = media_nodes.storage_id AND p.path = media_nodes.path
            ),
            playback_completed = (
              SELECT p.completed FROM media_playback_progress p
              WHERE p.storage_id = media_nodes.storage_id AND p.path = media_nodes.path
            ),
            last_played_at = (
              SELECT p.last_played_at FROM media_playback_progress p
              WHERE p.storage_id = media_nodes.storage_id AND p.path = media_nodes.path
            ),
            play_count = (
              SELECT p.play_count FROM media_playback_progress p
              WHERE p.storage_id = media_nodes.storage_id AND p.path = media_nodes.path
            )
        WHERE EXISTS (
          SELECT 1 FROM media_playback_progress p
          WHERE p.storage_id = media_nodes.storage_id AND p.path = media_nodes.path
        )
      ''');
      await db.customStatement('DROP TABLE media_playback_progress');
    }
  }

  // ── 2. playback_scenarios → scenario (rebuild, B1/D1/E4) ──

  Future<void> _migrateScenarios(Migrator m) async {
    if (!await _tableExists('playback_scenarios')) return;
    if (await _tableExists('scenario')) {
      // Already present (fresh path via v7) — nothing to rebuild.
      return;
    }

    final oldRows = await db.customSelect(
      'SELECT id, name, is_system_default, created_at, updated_at FROM playback_scenarios',
    ).get();

    // Pull definition config from the old states table (still under its name
    // at this point; it is renamed later in _migrateStates).
    final stateRows = await db.customSelect(
      'SELECT scenario_id, sort_field, sort_direction, "order", repeat_mode '
      'FROM playback_scenario_states',
    ).get();
    final stateConfig = <String, Map<String, Object?>>{};
    for (final r in stateRows) {
      stateConfig[r.read<String>('scenario_id')] = r.data;
    }

    await db.customStatement('ALTER TABLE playback_scenarios RENAME TO _old_scenarios');
    await m.createTable(db.scenariosTable);

    for (final row in oldRows) {
      final id = row.read<String>('id');
      final isSystemDefault = row.read<int>('is_system_default') == 1;
      final cfg = stateConfig[id] ?? {};
      final scenario = Scenario(
        id: id,
        name: row.read<String>('name'),
        type: isSystemDefault ? ScenarioKind.systemPlaying : ScenarioKind.userSaved,
        version: isSystemDefault ? null : 0,
        sortField: _scenarioSortField(cfg['sort_field'] as String?),
        sortDirection: (cfg['sort_direction'] as String?) == 'desc'
            ? SortDirection.desc
            : SortDirection.asc,
        order: (cfg['order'] as String?) == 'shuffled'
            ? PlaybackOrder.shuffled
            : PlaybackOrder.sequential,
        duplicatePolicy: DuplicatePolicy.allowDuplicate,
        repeatMode: _repeat(cfg['repeat_mode'] as String?),
        createdAt: row.read<DateTime?>('created_at'),
        updatedAt: row.read<DateTime?>('updated_at'),
      );
      await _insertScenario(scenario);
    }

    await db.customStatement('DROP TABLE _old_scenarios');
  }

  // ── 3. scenario_sources += sort_order (A4) ──

  Future<void> _migrateSources(Migrator m) async {
    if (!await _columnExists('scenario_sources', 'sort_order')) {
      await m.addColumn(db.scenarioSourcesTable, db.scenarioSourcesTable.sortOrder);
    }
    // Backfill sort_order from insertion id (monotonic proxy for add order).
    await db.customStatement(
      'UPDATE scenario_sources SET sort_order = id WHERE sort_order = 0',
    );
  }

  // ── 4. scenario_explicit_includes → scenario_explicit_items (rebuild, B1) ──

  Future<void> _migrateExplicitItems(Migrator m) async {
    if (!await _tableExists('scenario_explicit_includes')) return;
    if (await _tableExists('scenario_explicit_items')) return;

    final oldRows = await db.customSelect(
      'SELECT id, scenario_id, storage_id, path, media_id, created_at '
      'FROM scenario_explicit_includes',
    ).get();

    await db.customStatement(
      'ALTER TABLE scenario_explicit_includes RENAME TO _old_explicit_includes',
    );
    await m.createTable(db.scenarioExplicitItemsTable);

    for (final row in oldRows) {
      final scenarioId = row.read<String>('scenario_id');
      final path = row.read<String>('path');
      await db.into(db.scenarioExplicitItemsTable).insert(
            ScenarioExplicitItemsTableCompanion.insert(
              scenarioId: scenarioId,
              batchId: Value<String?>(scenarioId), // one synthetic batch per scenario
              storageId: row.read<String>('storage_id'),
              path: path,
              mediaId: Value(row.read<int?>('media_id')),
              addOrder: Value(row.read<int>('id')), // monotonic add-order proxy
              uiSortKey: Value<String?>(path.toLowerCase()),
              createdAt: Value(row.read<DateTime?>('created_at')),
            ),
          );
    }

    await db.customStatement('DROP TABLE _old_explicit_includes');
  }

  // ── 5. scenario_exclude_rules → scenario_excludes (rebuild, B1/F1) ──

  Future<void> _migrateExcludes(Migrator m) async {
    if (!await _tableExists('scenario_exclude_rules')) return;
    if (await _tableExists('scenario_excludes')) return;

    final oldRows = await db.customSelect(
      'SELECT id, scenario_id, kind, storage_id, path, recursive, created_at '
      'FROM scenario_exclude_rules',
    ).get();

    await db.customStatement(
      'ALTER TABLE scenario_exclude_rules RENAME TO _old_exclude_rules',
    );
    await m.createTable(db.scenarioExcludesTable);

    for (final row in oldRows) {
      await db.into(db.scenarioExcludesTable).insert(
            ScenarioExcludesTableCompanion.insert(
              scenarioId: row.read<String>('scenario_id'),
              scope: const Value(ExcludeScope.scenario),
              lifetime: const Value(ExcludeLifetime.persistent),
              sourceId: const Value(null),
              kind: _excludeKind(row.read<String>('kind')),
              storageId: row.read<String>('storage_id'),
              path: row.read<String>('path'),
              recursive: Value(row.read<bool>('recursive')),
              createdAt: Value(row.read<DateTime?>('created_at')),
            ),
          );
    }

    await db.customStatement('DROP TABLE _old_exclude_rules');
  }

  // ── 6. playback_scenario_states → scenario_state (rebuild, D4/E2) ──

  Future<void> _migrateStates(Migrator m) async {
    if (!await _tableExists('playback_scenario_states')) return;
    if (await _tableExists('scenario_state')) return;

    final oldRows = await db.customSelect(
      'SELECT scenario_id, current_storage_id, current_path, shuffle_seed, '
      'shuffle_version, shuffle_item_count, last_active_at '
      'FROM playback_scenario_states',
    ).get();

    await db.customStatement(
      'ALTER TABLE playback_scenario_states RENAME TO _old_states',
    );
    await m.createTable(db.scenarioStatesTable);

    for (final row in oldRows) {
      final storageId = row.read<String?>('current_storage_id');
      final path = row.read<String?>('current_path');
      PlaybackOccurrenceId? occurrence;
      if (storageId != null && path != null) {
        occurrence = PlaybackOccurrenceId(storageId: storageId, path: path);
      }
      await db.into(db.scenarioStatesTable).insert(
            ScenarioState(scenarioId: row.read<String>('scenario_id'))
                .copyWith(
              currentPlaybackOccurrence: occurrence,
              shuffleSeed: row.read<int?>('shuffle_seed'),
              shuffleVersion: row.read<int>('shuffle_version'),
              shuffleItemCount: row.read<int>('shuffle_item_count'),
              lastActiveAt: row.read<DateTime?>('last_active_at'),
            )
                .toCompanion(),
          );
    }

    await db.customStatement('DROP TABLE _old_states');
  }

  // ── 7. ensure the single SYSTEM_PLAYING row + state ──

  Future<void> _ensureSystemPlaying() async {
    final existing = await db.customSelect(
      "SELECT id FROM scenario WHERE type = 'systemPlaying' LIMIT 1",
    ).get();
    if (existing.isNotEmpty) return;

    final now = DateTime.now();
    final scenario = Scenario(
      id: '${now.microsecondsSinceEpoch}-system',
      name: 'Playing',
      type: ScenarioKind.systemPlaying,
      version: null,
      createdAt: now,
      updatedAt: now,
    );
    await _insertScenario(scenario);
    await db.into(db.scenarioStatesTable).insert(
          ScenarioState(scenarioId: scenario.id).toCompanion(),
        );
    areaKeyLog.i('Created SystemPlayingScenario: ${scenario.id}');
  }

  // ── helpers ──

  Future<void> _insertScenario(Scenario scenario) {
    return db.into(db.scenariosTable).insert(scenario.toCompanion());
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

  // Enum parse helpers (nullable DB → domain defaults).
  static ScenarioSortField _scenarioSortField(String? v) {
    for (final f in ScenarioSortField.values) {
      if (f.name == v) return f;
    }
    return ScenarioSortField.name;
  }

  static Repeat _repeat(String? v) {
    for (final r in Repeat.values) {
      if (r.name == v) return r;
    }
    return Repeat.none;
  }

  static ExcludeRuleKind _excludeKind(String v) {
    for (final k in ExcludeRuleKind.values) {
      if (k.name == v) return k;
    }
    return ExcludeRuleKind.media;
  }
}

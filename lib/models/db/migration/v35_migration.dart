import 'package:drift/drift.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/migration/migration_guards.dart';
import 'package:iris/utils/logger.dart';

final _log = AreaKeyLog(LogKeys.legacyDb);

/// Schema v35: index-only migration.
///
/// Two independent read paths were doing full scans or temp-b-tree sorts:
///
/// 1. Scope-keyed media_nodes sorts. v31 added `(data_scope_id, …)` indexes
///    only for `parent_path` / `name` / `normalized_name` / `path_depth`, but
///    the browser also sorts by `size_in_bytes`, `modified_at` and
///    `duration_ms` (the UI-exposed `SortBy` + `ScenarioSortField` values).
///    Those fell back to scanning the whole scope and sorting in a temp B-tree.
///    Only the user-facing sort columns get a scope index; internal-only
///    columns (`created_at`, `pixel_count`, aggregate totals, `path`) are
///    deliberately left alone to avoid write amplification on a table that
///    already carries ~28 indexes.
///
/// 2. Feature tables whose hot lookups had no usable index:
///    `scenario_excludes` (read on EVERY scenario resolve), `video_tag_members`
///    (`storage_id`/`path` filtering and `added_at` ordering),
///    `bg_mapping_segments.mapping_id` (SQLite does not index FKs) and
///    `media_lib_sources.storage_id`.
///
/// Index-only: no table is rebuilt and no column changes, so the migration is
/// trivially data-preserving. Idempotent (`IF NOT EXISTS`).
class MigrationV35 {
  final AppDatabase db;
  MigrationV35(this.db);

  Future<void> run(Migrator m) async {
    await createPerfIndexes(db);
  }

  /// Idempotent; also called from `onCreate` so fresh installs get them.
  static Future<void> createPerfIndexes(AppDatabase db) async {
    final statements = <String>[
      // ── media_nodes: scope-keyed UI sort columns ──
      // Flat ordering (ORDER BY <sortCol>) per scope.
      'CREATE INDEX IF NOT EXISTS idx_scope_sort_size ON media_nodes(data_scope_id, size_in_bytes);',
      'CREATE INDEX IF NOT EXISTS idx_scope_sort_modified ON media_nodes(data_scope_id, modified_at);',
      'CREATE INDEX IF NOT EXISTS idx_scope_sort_duration ON media_nodes(data_scope_id, duration_ms);',
      // 同目录连续 (pathGroupFirst): ORDER BY (parent_path, <sortCol>, name).
      'CREATE INDEX IF NOT EXISTS idx_scope_parent_size_sort ON media_nodes(data_scope_id, parent_path, size_in_bytes);',
      'CREATE INDEX IF NOT EXISTS idx_scope_parent_modified_sort ON media_nodes(data_scope_id, parent_path, modified_at);',
      'CREATE INDEX IF NOT EXISTS idx_scope_parent_duration_sort ON media_nodes(data_scope_id, parent_path, duration_ms);',

      // ── scenario_excludes: every resolve filters by scenario_id ──
      'CREATE INDEX IF NOT EXISTS idx_scenario_excludes_scenario ON scenario_excludes(scenario_id);',

      // ── video_tag_members: path lookup + retention ordering ──
      'CREATE INDEX IF NOT EXISTS idx_tag_members_storage_path ON video_tag_members(storage_id, path);',
      'CREATE INDEX IF NOT EXISTS idx_tag_members_tag_added ON video_tag_members(tag_id, added_at);',

      // ── bg_mapping_segments: FK lookup (SQLite does not auto-index FKs) ──
      'CREATE INDEX IF NOT EXISTS idx_bg_mapping_segments_mapping ON bg_mapping_segments_table(mapping_id);',

      // ── media_lib_sources: storage-scoped lookup ──
      'CREATE INDEX IF NOT EXISTS idx_lib_sources_storage ON media_lib_sources(storage_id);',
    ];
    for (final stmt in statements) {
      try {
        await db.customStatement(stmt);
      } catch (e) {
        // A hand-built/partial legacy database need not carry every feature
        // table; an index is a pure performance artifact, so its absence is
        // tolerated. Every other failure (disk full, lock, corruption) must
        // abort so drift rolls the schema version back and the next open
        // retries.
        if (!isMissingSchemaObject(e)) {
          _log.e('MigrationV35: index failed', e);
          rethrow;
        }
        _log.w('MigrationV35: index skipped, object absent: $e');
      }
    }
  }
}

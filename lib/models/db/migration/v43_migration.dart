import 'package:drift/drift.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/utils/logger.dart';

final _log = AreaKeyLog(LogKeys.legacyDb);

/// Schema v43: the derived index stops carrying long TEXT keys.
///
/// - `scenario_queue_entries` is keyed by `build_id` ALONE (the 36-char
///   scenario UUID was on every row AND in every index entry).
/// - `vm_group_members` references its group by an integer `group_seq` instead
///   of the ~60-char `ruleId|rootPath|#chunkNo` scopeKey; `vm_groups` keeps the
///   string once per group.
///
/// The derived index is a rebuildable cache, so this DROPS and recreates the
/// tables (and clears the now-stale build rows) instead of migrating data.
/// Idempotent; `createIndexes` is also called from `_createIndexes` so a fresh
/// install converges on the same shape.
class MigrationV43 {
  final AppDatabase db;

  MigrationV43(this.db);

  Future<void> run(Migrator m) async {
    try {
      await db.customStatement('DROP TABLE IF EXISTS scenario_queue_entries');
      await db.customStatement('''
        CREATE TABLE IF NOT EXISTS scenario_queue_entries (
          anchor_rank INTEGER NOT NULL,
          is_group INTEGER NOT NULL DEFAULT 0,
          group_id TEXT,
          media_node_id INTEGER,
          placeholder_storage_id TEXT,
          placeholder_path TEXT,
          occurrence_index INTEGER NOT NULL DEFAULT 0,
          flags INTEGER NOT NULL DEFAULT 0,
          build_id INTEGER NOT NULL,
          PRIMARY KEY (build_id, anchor_rank)
        );
      ''');
      await db.customStatement('DROP TABLE IF EXISTS vm_group_members');
      await db.customStatement('''
        CREATE TABLE IF NOT EXISTS vm_group_members (
          group_seq INTEGER NOT NULL,
          in_group_rank INTEGER NOT NULL,
          media_node_id INTEGER NOT NULL,
          occurrence_index INTEGER NOT NULL DEFAULT 0,
          build_id INTEGER NOT NULL,
          PRIMARY KEY (group_seq, in_group_rank, build_id)
        );
      ''');
      await db.customStatement('DROP TABLE IF EXISTS vm_groups');
      await db.customStatement('''
        CREATE TABLE IF NOT EXISTS vm_groups (
          group_id TEXT NOT NULL,
          group_seq INTEGER NOT NULL,
          rule_id TEXT NOT NULL,
          anchor_root TEXT NOT NULL DEFAULT '',
          display_seq INTEGER NOT NULL,
          segment_count INTEGER NOT NULL,
          total_duration_ms INTEGER NOT NULL DEFAULT 0,
          total_size_bytes INTEGER NOT NULL DEFAULT 0,
          build_id INTEGER NOT NULL,
          PRIMARY KEY (group_id, build_id)
        );
      ''');
      // The dropped generations' builds are stale: clear them so a fresh
      // generation is built and no orphan meta survives.
      await db.customStatement('DELETE FROM scenario_queue_builds');
    } catch (e) {
      // Do NOT swallow: a missing or half-built derived table would only
      // surface later as a confusing DAO failure. Rethrowing rolls the whole
      // migration back (user_version stays at the previous value), so the next
      // open retries cleanly.
      _log.e('MigrationV43: recreate derived tables failed', e);
      rethrow;
    }
    await createIndexes(db);
  }

  /// The seek indexes the recreated tables need. Paging itself is served by the
  /// `(build_id, anchor_rank)` PK.
  static Future<void> createIndexes(AppDatabase db) async {
    const statements = <String>[
      // occurrence lookup, and the tag/search joins.
      'CREATE INDEX IF NOT EXISTS idx_scenario_queue_node '
          'ON scenario_queue_entries(build_id, media_node_id)',
      // rebuild/evict a rule's group generation.
      'CREATE INDEX IF NOT EXISTS idx_vm_groups_rule_build '
          'ON vm_groups(rule_id, build_id)',
      // reverse-lookup a file's group (overlay/preflight).
      'CREATE INDEX IF NOT EXISTS idx_vm_group_members_node_build '
          'ON vm_group_members(media_node_id, build_id)',
    ];
    for (final stmt in statements) {
      try {
        await db.customStatement(stmt);
      } catch (e) {
        _log.w('MigrationV43: index failed: $e');
      }
    }
  }
}

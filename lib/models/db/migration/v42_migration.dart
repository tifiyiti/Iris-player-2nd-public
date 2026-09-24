import 'package:drift/drift.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/migration/migration_guards.dart';
import 'package:iris/utils/logger.dart';

final _log = AreaKeyLog(LogKeys.legacyDb);

/// Schema v42: drops three REDUNDANT derived-index indexes.
///
/// They duplicated a prefix of an existing primary key (a rowid table's PK is
/// itself a unique index), so every one of them was another full B-tree of
/// `scenario_id` + rank/build key per row — the bulk of the derived storage at
/// 500k files.
///
/// - `idx_scenario_queue_seek(scenario_id, build_id, anchor_rank)` — the PK
///   `(scenario_id, anchor_rank, build_id)` already answers the paged read in
///   order (verified with EXPLAIN QUERY PLAN: no temp B-tree).
/// - `idx_scenario_queue_build(scenario_id, build_id)` — a PK prefix;
///   `MAX(build_id)` now reads `scenario_queue_builds` instead.
/// - `idx_vm_group_members_group_build(group_id, build_id)` — the PK
///   `(group_id, in_group_rank, build_id)` already serves group-member reads.
///
/// The index is a rebuildable cache, so no data migration is needed.
/// Idempotent; also invoked from `_createIndexes` so a fresh install (which
/// creates the v39 set first) converges on the same shape.
class MigrationV42 {
  final AppDatabase db;

  MigrationV42(this.db);

  static const _redundant = <String>[
    'idx_scenario_queue_seek',
    'idx_scenario_queue_build',
    'idx_vm_group_members_group_build',
  ];

  Future<void> run(Migrator m) => dropRedundantIndexes(db);

  /// Idempotent `DROP INDEX IF EXISTS` for the redundant set.
  static Future<void> dropRedundantIndexes(AppDatabase db) async {
    for (final name in _redundant) {
      try {
        await db.customStatement('DROP INDEX IF EXISTS $name');
      } catch (e) {
        // A hand-built/partial legacy database need not carry every feature
        // table, so an absent index/table is tolerated. Every other failure
        // must abort so drift rolls the schema version back and the next open
        // retries.
        if (!isMissingSchemaObject(e)) {
          _log.e('MigrationV42: drop $name failed', e);
          rethrow;
        }
        _log.w('MigrationV42: drop $name skipped, object absent: $e');
      }
    }
  }
}

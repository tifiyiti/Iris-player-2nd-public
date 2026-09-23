import 'package:drift/drift.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/utils/logger.dart';

final _log = AreaKeyLog(LogKeys.legacyDb);

/// Schema v45: the v39/v43 row-based derived index is RETIRED.
///
/// The shared-order index (v44) is the only persisted representation: two blobs
/// per scenario reproduce every read the row tables served, at a fraction of the
/// size, and a scenario the representation cannot express degrades to the legacy
/// walk instead of to rows nothing writes any more.
///
/// Drops `scenario_queue_entries`, `vm_groups` and `vm_group_members`; their
/// seek indexes go with them. Two things are deliberately NOT touched:
///
/// - `scenario_queue_builds` — the build meta IS the live generation the read
///   paths resolve (`currentBuildId`) and the shared index's GC key. Unlike
///   v43's recreate, nothing here invalidates it.
/// - `scenario_shared_index` / `media_orders` — the existing shared index stays
///   valid across the upgrade, so an upgraded library keeps serving its queues
///   without a rebuild. Rows whose scenario is deleted later are collected by
///   the shared index's own GC.
///
/// Idempotent (`DROP TABLE IF EXISTS`), so it is safe to re-run and safe on a
/// database that already lost the tables for any reason.
class MigrationV45 {
  final AppDatabase db;

  MigrationV45(this.db);

  /// The retired row tables, exposed so the migration test can assert the exact
  /// set that must no longer exist.
  static const List<String> droppedTables = <String>[
    'scenario_queue_entries',
    'vm_group_members',
    'vm_groups',
  ];

  Future<void> run(Migrator m) async {
    try {
      for (final table in droppedTables) {
        await db.customStatement('DROP TABLE IF EXISTS $table');
      }
    } catch (e) {
      // Do NOT swallow: a half-applied schema would surface later as an
      // inexplicable DAO failure. Rethrowing aborts the open before drift stamps
      // the new version, so the database stays on 44 and the next open retries.
      _log.e('MigrationV45: dropping the retired derived tables failed', e);
      rethrow;
    }
  }
}

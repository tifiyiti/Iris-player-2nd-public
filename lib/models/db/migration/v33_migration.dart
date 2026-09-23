import 'package:drift/drift.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/utils/logger.dart';

final _log = AreaKeyLog(LogKeys.legacyDb);

/// Schema v33: indexes for the `vm_progress` non-PK deletes.
///
/// `deleteForScopeKey` (session stop paths) and `deleteForRule` (rule
/// cascade) filter on non-PK columns — without indexes they full-scan.
/// Re-entrant (`IF NOT EXISTS`); fresh installs get them via
/// [createVmProgressIndexes] from `onCreate`.
class MigrationV33 {
  final AppDatabase db;
  MigrationV33(this.db);

  Future<void> run(Migrator m) async {
    await createVmProgressIndexes(db);
  }

  static Future<void> createVmProgressIndexes(AppDatabase db) async {
    for (final statement in [
      'CREATE INDEX IF NOT EXISTS idx_vm_progress_scope_key ON vm_progress(scope_key)',
      'CREATE INDEX IF NOT EXISTS idx_vm_progress_rule ON vm_progress(rule_id)',
    ]) {
      try {
        await db.customStatement(statement);
      } catch (e) {
        _log.w('MigrationV33: $e');
      }
    }
  }
}

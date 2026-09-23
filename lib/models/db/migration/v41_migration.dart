import 'package:drift/drift.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/utils/logger.dart';

final _log = AreaKeyLog(LogKeys.legacyDb);

/// Schema v41: `app_meta` — a tiny cross-restart key/value table.
///
/// The derived queue index is persisted, but its validity signature used to
/// live only in memory, so every cold start rebuilt the first-viewed scenario
/// from scratch. Persisting the content revision + per-generation signature
/// lets a fresh process reuse the stored generation instead.
///
/// Idempotent (`IF NOT EXISTS`), also reached by `onCreate` via `createAll()`.
class MigrationV41 {
  final AppDatabase db;

  MigrationV41(this.db);

  Future<void> run(Migrator m) async {
    try {
      await db.customStatement(
        'CREATE TABLE IF NOT EXISTS app_meta ('
        'key TEXT NOT NULL PRIMARY KEY, value TEXT NOT NULL)',
      );
    } catch (e) {
      _log.w('MigrationV41: app_meta failed: $e');
    }
  }
}

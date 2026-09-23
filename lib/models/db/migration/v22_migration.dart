import 'package:drift/drift.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/utils/logger.dart';

final _log = AreaKeyLog(LogKeys.legacyDb);

/// Schema v22: scan queue table for 50w-scale resumable scans.
///
/// Creates `scan_queue` (storage_id, path, depth, status). Re-entrant.
/// Existing `media_nodes.scan_state` stays for per-dir done marking.
class MigrationV22 {
  final AppDatabase db;
  MigrationV22(this.db);

  Future<void> run(Migrator m) async {
    final has = await _hasTable('scan_queue');
    if (has == true) return;
    _log.i('MigrationV22: creating scan_queue');
    try {
      await db.customStatement('''
        CREATE TABLE IF NOT EXISTS scan_queue (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          storage_id TEXT NOT NULL,
          path TEXT NOT NULL,
          depth INTEGER NOT NULL,
          status TEXT NOT NULL DEFAULT 'pending',
          discovered_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          updated_at TEXT,
          UNIQUE(storage_id, path)
        )
      ''');
      await db.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_scan_queue_storage_status ON scan_queue(storage_id, status, depth)');
    } catch (e) {
      _log.w('MigrationV22: create failed: $e');
    }
  }

  Future<bool?> _hasTable(String name) async {
    try {
      final rows = await db.customSelect(
        'SELECT name FROM sqlite_master WHERE type = ? AND name = ?',
        variables: <Variable>[
          Variable.withString('table'),
          Variable.withString(name)
        ],
      ).get();
      return rows.isNotEmpty;
    } catch (_) {
      return null;
    }
  }
}

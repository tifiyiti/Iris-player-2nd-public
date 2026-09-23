import 'package:drift/drift.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/utils/logger.dart';

final _log = AreaKeyLog(LogKeys.legacyDb);

/// Schema v44: the shared media orders that back the shared-order derived index.
///
/// Create-only for now. The shared-order index is built ALONGSIDE the v43
/// row-based index; the old tables are dropped only once the new read path is
/// the default (a later migration), so this step is safe to ship on its own.
class MigrationV44 {
  final AppDatabase db;

  MigrationV44(this.db);

  Future<void> run(Migrator m) async {
    try {
      await db.customStatement('''
        CREATE TABLE IF NOT EXISTS media_orders (
          order_key TEXT NOT NULL,
          media_rev INTEGER NOT NULL DEFAULT 0,
          n INTEGER NOT NULL,
          ids BLOB NOT NULL,
          PRIMARY KEY (order_key)
        );
      ''');
      await db.customStatement('''
        CREATE TABLE IF NOT EXISTS scenario_shared_index (
          build_id INTEGER NOT NULL,
          base_count INTEGER NOT NULL,
          slices BLOB NOT NULL,
          accepted BLOB NOT NULL,
          absorbed BLOB NOT NULL,
          group_rows BLOB NOT NULL,
          placeholders BLOB NOT NULL,
          occurrence BLOB NOT NULL,
          flags BLOB NOT NULL,
          PRIMARY KEY (build_id)
        );
      ''');
    } catch (e) {
      // Same reasoning as MigrationV43: a half-created table must not be left
      // behind silently — rethrow so the migration rolls back and retries.
      _log.e('MigrationV44: create media_orders failed', e);
      rethrow;
    }
  }
}

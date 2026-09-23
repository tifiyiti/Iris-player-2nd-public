import 'package:drift/drift.dart';
import 'package:iris/models/db/app_database.dart';

class MigrationV5 {
  final AppDatabase db;

  MigrationV5(this.db);

  Future<void> run(Migrator m) async {
    await db.transaction(() async {
      await _migrateMediaNodes(m);
    });
  }

  Future<void> _migrateMediaNodes(Migrator m) async {
    await db.customStatement('ALTER TABLE media_nodes RENAME TO _old_nodes;');

    await m.createTable(db.mediaNodesTable);

    await db.customStatement('''
      INSERT INTO media_nodes (
        id,
        storage_id,
        path,
        parent_path,
        path_depth,
        name,
        normalized_name,
        node_kind,
        media_type,
        size_in_bytes,
        duration_ms,
        direct_media_count,
        direct_dir_count,
        direct_item_count,
        total_media_count,
        total_dir_count,
        total_item_count,
        total_size_in_bytes,
        total_duration_ms,
        modified_at,
        created_at,
        is_present,
        last_seen_at,
        is_scan_done,
        last_scan_at
      )
      SELECT
        id,
        storage_id,
        path,
        parent_path,
        path_depth,
        name,
        normalized_name,
        node_kind,
        media_type,
        size_in_bytes,
        duration_ms,
        direct_media_count,
        direct_dir_count,
        direct_item_count,
        total_media_count,
        total_dir_count,
        total_item_count,
        total_size_in_bytes,
        total_duration_ms,
        modified_at,
        created_at,
        is_present,
        last_seen_at,
        0,
        NULL
      FROM _old_nodes;
    ''');

    await db.customStatement('DROP TABLE _old_nodes;');
  }
}

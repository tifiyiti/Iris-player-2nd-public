import 'package:drift/drift.dart';
import 'package:iris/models/db/app_database.dart';

class MigrationV4 {
  final AppDatabase db;

  MigrationV4(this.db);

  // ENTRY
  Future<void> run(Migrator m) async {
    await db.transaction(() async {
      await _dropOldIndexes();
      await _migrateMediaLibSources(m);
      await _migrateMediaNodes(m);
      await createNewIndexes();
    });
  }

  Future<void> _dropOldIndexes() async {
    final indexes = [
      'idx_media_storage_path',
      'idx_media_parent',
      'idx_media_parent_sort',
      'idx_media_name',
      'idx_media_type',
      'idx_media_modified',
      'idx_lib_sources',
      'idx_node_parent_name',
      'idx_node_parent_size',
      'idx_node_parent_duration',
      'idx_node_parent_modified',
      'idx_node_global_media',
      'idx_node_global_dirs',
    ];

    for (final idx in indexes) {
      await db.customStatement('DROP INDEX IF EXISTS $idx;');
    }
  }

  Future<void> _migrateMediaLibSources(Migrator m) async {
    await db.customStatement('ALTER TABLE media_lib_sources RENAME TO _old_sources;');

    await m.createTable(db.mediaLibSourcesTable);

    await db.customStatement('''
      INSERT INTO media_lib_sources (
        id,
        library_id,
        storage_id,
        path,
        path_depth,
        media_source_kind,
        total_media_count,
        total_dir_count,
        total_item_count,
        total_size_in_bytes,
        total_duration_ms,
        modified_at,
        created_at
      )
      SELECT
        id,
        library_id,
        storage_id,
        path,
        0,                                   -- path_depth (will be updated later if needed)
        CASE kind
          WHEN 0 THEN 'storage'
          WHEN 1 THEN 'directory'
          WHEN 2 THEN 'file'
          ELSE NULL
        END,
        0, 0, 0, 0, 0,                       -- aggregates start at 0
        NULL,                                -- 旧表没有 modified_at，直接填 NULL
        NULL                                 -- 旧表没有 created_at，直接填 NULL
      FROM _old_sources;
    ''');

    await db.customStatement('DROP TABLE _old_sources;');
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
        last_seen_at
      )
      SELECT
        id,
        storage_id,
        path,
        parent_path,
        0,                                      -- path_depth (can be backfilled later)
        name,
        LOWER(name),
        CASE 
          WHEN is_dir = 1 THEN 'directory' 
          ELSE 'file' 
        END,
        CASE media_type 
          WHEN 0 THEN 'video' 
          WHEN 1 THEN 'audio' 
          ELSE NULL 
        END,
        size,
        duration,
        0, 0, 0,                                -- direct_* counts
        0, 0, 0,                                -- total_* counts (will be populated by scan)
        0, 0,                                   -- total size + duration
        NULL,
        NULL,                                   -- created_at (wasn't in old schema)
        "exists",                               -- mapped to is_present (ESCAPED)
        last_seen_at
      FROM _old_nodes;
    ''');

    await db.customStatement('DROP TABLE _old_nodes;');
  }

  Future<void> createNewIndexes() async {
    final statements = [
      // Core lookup
      'CREATE INDEX IF NOT EXISTS idx_media_storage_path ON media_nodes(storage_id, path);',
      'CREATE INDEX IF NOT EXISTS idx_media_parent ON media_nodes(storage_id, parent_path);',
      'CREATE INDEX IF NOT EXISTS idx_node_parent_name ON media_nodes(storage_id, parent_path, name);',

      // Sorting indexes (very important for pagination + sort)
      'CREATE INDEX IF NOT EXISTS idx_node_parent_name_sort ON media_nodes(storage_id, parent_path, normalized_name);',
      'CREATE INDEX IF NOT EXISTS idx_node_parent_size_sort ON media_nodes(storage_id, parent_path, size_in_bytes);',
      'CREATE INDEX IF NOT EXISTS idx_node_parent_duration_sort ON media_nodes(storage_id, parent_path, duration_ms);',
      'CREATE INDEX IF NOT EXISTS idx_node_parent_modified_sort ON media_nodes(storage_id, parent_path, modified_at);',

      // Global views
      'CREATE INDEX IF NOT EXISTS idx_node_kind ON media_nodes(node_kind);',
      'CREATE INDEX IF NOT EXISTS idx_node_global_media ON media_nodes(node_kind, media_type, normalized_name);',
      'CREATE INDEX IF NOT EXISTS idx_node_global_dirs ON media_nodes(node_kind, total_size_in_bytes DESC);',

      'CREATE INDEX IF NOT EXISTS idx_node_media_type ON media_nodes(media_type);',
      'CREATE INDEX IF NOT EXISTS idx_node_media_size ON media_nodes(size_in_bytes);',
      'CREATE INDEX IF NOT EXISTS idx_node_media_sort_size ON media_nodes(media_type, size_in_bytes);',
      'CREATE INDEX IF NOT EXISTS idx_node_media_duration ON media_nodes(duration_ms);',
      'CREATE INDEX IF NOT EXISTS idx_node_media_sort_duration ON media_nodes(media_type, duration_ms);',
      'CREATE INDEX IF NOT EXISTS idx_node_media_nodes_modified ON media_nodes(modified_at);',
      'CREATE INDEX IF NOT EXISTS idx_node_media_sort_modified ON media_nodes(media_type, modified_at);',

      'CREATE INDEX IF NOT EXISTS idx_node_total_size ON media_nodes(total_size_in_bytes);',
      'CREATE INDEX IF NOT EXISTS idx_node_total_duration ON media_nodes(total_duration_ms);',
      'CREATE INDEX IF NOT EXISTS idx_node_total_items ON media_nodes(total_item_count);',
      'CREATE INDEX IF NOT EXISTS idx_node_total_media ON media_nodes(total_media_count);',
      'CREATE INDEX IF NOT EXISTS idx_node_created ON media_nodes(created_at);',
      'CREATE INDEX IF NOT EXISTS idx_node_path ON media_nodes(path);',

      // Normalized search
      'CREATE INDEX IF NOT EXISTS idx_node_normalized_name ON media_nodes(normalized_name);',

      // Depth + storage
      'CREATE INDEX IF NOT EXISTS idx_node_depth ON media_nodes(storage_id, path_depth);',

      // Sources
      'CREATE INDEX IF NOT EXISTS idx_lib_sources ON media_lib_sources(library_id, storage_id);',
      'CREATE INDEX IF NOT EXISTS idx_lib_sources_path ON media_lib_sources(library_id, path);',
    ];

    for (final stmt in statements) {
      await db.customStatement(stmt);
    }
  }
}

import 'package:drift/drift.dart';
import 'package:iris/models/db/app_database.dart';

class MigrationV2 {
  final AppDatabase db;
  MigrationV2(this.db);

  Future<void> run(Migrator m) async {
    await m.createTable(db.mediaNodesTable);
    await m.createTable(db.scanStatesTable);
    await m.createTable(db.mediaLibsTable);
    await m.createTable(db.mediaLibSourcesTable);

    await createNewIndexes();
  }

  Future<void> createNewIndexes() async {
    // MediaNodes indexes

    // Fast lookup by exact node path.
    await db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_media_storage_path
      ON media_nodes(storage_id, path)
    ''');

    // Fast listing of directory contents, already sorted by name.
    await db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_media_parent_sort
      ON media_nodes(storage_id, parent_path, name)
    ''');

    // Fast filtering by directory.
    await db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_media_parent
      ON media_nodes(storage_id, parent_path)
    ''');

    // Fast name search.
    await db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_media_name
      ON media_nodes(name)
    ''');

    // Fast filtering by media type.
    await db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_media_type
      ON media_nodes(media_type)
    ''');

    // Fast sorting by modification time.
    await db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_media_modified
      ON media_nodes(modified_at)
    ''');

    // ScanStates indexes

    // Fast lookup of scan state by directory.
    await db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_scan_storage_path
      ON scan_states(storage_id, path)
    ''');

    // Media Library Source indexes

    // Fast lookup of sources belonging to a library.
    await db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_lib_sources
      ON media_lib_sources(library_id, storage_id)
    ''');
  }
}

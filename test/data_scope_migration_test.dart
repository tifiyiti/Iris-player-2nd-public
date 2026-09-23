import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/model/db/dao/media_nodes_dao.dart';
import 'package:iris/features/media_library/model/db/dao/scan_queue_dao.dart';
import 'package:iris/features/media_library/model/media_lib/media_node.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/migration/v31_migration.dart';
import 'package:iris/models/db/storage_scope.dart';

Future<Set<String>> _columns(AppDatabase db, String table) async {
  final rows = await db.customSelect('PRAGMA table_info($table)').get();
  return rows.map((row) => row.read<String>('name')).toSet();
}

MediaNode _file(String storageId, String path) {
  final segments = path.split('/');
  return MediaNode.file(
    id: '$storageId:$path',
    storageId: storageId,
    path: segments,
    parentPath:
        segments.length == 1 ? null : segments.sublist(0, segments.length - 1).join('/'),
    pathDepth: segments.length,
    name: segments.last,
    mediaType: MediaType.video,
  );
}

/// Recreates the pre-v31 `media_nodes` shape (keyed by storage_id) so the
/// rebuild path can be exercised on a live database.
Future<void> _installLegacyMediaNodes(AppDatabase db) async {
  await db.customStatement('DROP TABLE media_nodes');
  await db.customStatement('''
    CREATE TABLE media_nodes (
      id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      storage_id TEXT NOT NULL,
      path TEXT NOT NULL,
      parent_path TEXT,
      path_depth INTEGER NOT NULL DEFAULT 0,
      name TEXT NOT NULL,
      normalized_name TEXT,
      node_kind TEXT NOT NULL,
      media_type TEXT,
      size_in_bytes INTEGER,
      duration_ms INTEGER,
      direct_media_count INTEGER NOT NULL DEFAULT 0,
      direct_dir_count INTEGER NOT NULL DEFAULT 0,
      direct_item_count INTEGER NOT NULL DEFAULT 0,
      total_media_count INTEGER NOT NULL DEFAULT 0,
      total_dir_count INTEGER NOT NULL DEFAULT 0,
      total_item_count INTEGER NOT NULL DEFAULT 0,
      total_size_in_bytes INTEGER NOT NULL DEFAULT 0,
      total_duration_ms INTEGER NOT NULL DEFAULT 0,
      modified_at INTEGER,
      created_at INTEGER,
      is_present INTEGER NOT NULL DEFAULT 1,
      last_seen_at INTEGER,
      is_scan_done INTEGER NOT NULL DEFAULT 0,
      last_scan_at INTEGER,
      scan_state TEXT NOT NULL DEFAULT 'notScan',
      playback_position_ms INTEGER,
      playback_completed INTEGER NOT NULL DEFAULT 0,
      last_played_at INTEGER,
      play_count INTEGER NOT NULL DEFAULT 0,
      history_restore_budget INTEGER,
      UNIQUE(storage_id, path)
    )
  ''');
}

void main() {
  group('v31 migration', () {
    test('storages_table gains a nullable data_scope_id', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.customSelect('SELECT 1').get();

      expect(await _columns(db, 'storages_table'), contains('data_scope_id'));
    });

    test('rebuilds media_nodes onto (data_scope_id, path) and back-fills',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await _installLegacyMediaNodes(db);
      await db.customStatement(
        "INSERT INTO media_nodes (storage_id, path, name, node_kind, media_type) "
        "VALUES ('s1', 'a/b.mp4', 'b.mp4', 'file', 'video')",
      );

      await MigrationV31(db).run(db.createMigrator());

      expect(await _columns(db, 'media_nodes'), contains('data_scope_id'));
      final row = await db
          .customSelect(
              "SELECT storage_id, data_scope_id FROM media_nodes WHERE path = 'a/b.mp4'")
          .getSingle();
      expect(row.read<String>('storage_id'), 's1');
      expect(row.read<String>('data_scope_id'), 's1');
    });

    test('the new unique key is (data_scope_id, path), not storage_id',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await _installLegacyMediaNodes(db);
      await MigrationV31(db).run(db.createMigrator());

      // Same path, different writer id, SAME scope → must collide.
      await db.customStatement(
        "INSERT INTO media_nodes (storage_id, data_scope_id, path, name, node_kind) "
        "VALUES ('s2', 'sc', 'x/v.mp4', 'v.mp4', 'file')",
      );
      await expectLater(
        db.customStatement(
          "INSERT INTO media_nodes (storage_id, data_scope_id, path, name, node_kind) "
          "VALUES ('s3', 'sc', 'x/v.mp4', 'v.mp4', 'file')",
        ),
        throwsA(anything),
      );
    });

    test('is re-entrant: a second run is a no-op', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await _installLegacyMediaNodes(db);
      await MigrationV31(db).run(db.createMigrator());
      await MigrationV31(db).run(db.createMigrator());

      final cols = await _columns(db, 'media_nodes');
      expect(cols.where((c) => c == 'data_scope_id'), hasLength(1));
    });

    test('back-fills a scope column that already exists but is NULL', () async {
      // Path taken when an older rebuild migration (v9/v15/v23) created the
      // table from the latest schema: the column exists, every row is NULL.
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.customSelect('SELECT 1').get();
      await db.customStatement(
        "INSERT INTO media_nodes (storage_id, path, name, node_kind) "
        "VALUES ('s1', 'a/b.mp4', 'b.mp4', 'file')",
      );

      final before = await db
          .customSelect(
              "SELECT data_scope_id FROM media_nodes WHERE path = 'a/b.mp4'")
          .getSingle();
      expect(before.read<String?>('data_scope_id'), isNull);

      await MigrationV31(db).run(db.createMigrator());

      final after = await db
          .customSelect(
              "SELECT data_scope_id FROM media_nodes WHERE path = 'a/b.mp4'")
          .getSingle();
      expect(after.read<String>('data_scope_id'), 's1');
    });
  });

  group('StorageScope translation', () {
    setUp(() => StorageScope.reset());
    tearDown(() => StorageScope.reset());

    test('nodes written via one entry are shared under the scope', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final dao = MediaNodesDao(db);
      addTearDown(db.close);

      // Entry 'b' is linked to canonical scope 'a'.
      StorageScope.resolver = (id) => id == 'b' ? 'a' : id;

      await dao.insertNode(_file('b', 'x/v.mp4'));

      final raw = await db
          .customSelect(
              "SELECT storage_id, data_scope_id FROM media_nodes WHERE path = 'x/v.mp4'")
          .getSingle();
      expect(raw.read<String>('storage_id'), 'a'); // canonical scope identity
      expect(raw.read<String>('data_scope_id'), 'a'); // shared scope

      // Either entry resolves the shared row.
      expect(await dao.getByPath('a', 'x/v.mp4'), isNotNull);
      expect(await dao.getByPath('b', 'x/v.mp4'), isNotNull);

      // Upserting through 'b' must not create a duplicate row.
      await dao.upsertNode(_file('b', 'x/v.mp4'));
      final count = await db
          .customSelect("SELECT COUNT(*) c FROM media_nodes WHERE path = 'x/v.mp4'")
          .getSingle();
      expect(count.read<int>('c'), 1);

      // A scope-scoped delete is visible to both entries.
      await dao.deleteNode('a', 'x/v.mp4');
      expect(await dao.getByPath('b', 'x/v.mp4'), isNull);
    });

    test('scan queue is shared across a scope', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final dao = ScanQueueDao(db);
      addTearDown(db.close);

      StorageScope.resolver = (id) => id == 'b' ? 'a' : id;
      await dao.enqueue('b', const ['x', 'x/y'], 1);

      expect(await dao.getPendingPaths('a'), containsAll(<String>['x', 'x/y']));
      expect(await dao.getPendingPaths('b'), containsAll(<String>['x', 'x/y']));
      expect(await dao.countAll('a'), 2);

      await dao.clearForStorage('a');
      expect(await dao.countAll('b'), 0);
    });

    test('reassignStorageIdForScope re-points rows, scope unchanged',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      final dao = MediaNodesDao(db);
      addTearDown(db.close);

      StorageScope.resolver = (id) => id == 'b' ? 'a' : id;
      await dao.insertNode(_file('b', 'x/v.mp4'));

      await dao.reassignStorageIdForScope(scopeId: 'a', newStorageId: 'c');

      final row = await dao.getByPath('a', 'x/v.mp4');
      expect(row, isNotNull);
      expect(row!.storageId, 'c');
      expect(row.dataScopeId, 'a');
    });
  });
}

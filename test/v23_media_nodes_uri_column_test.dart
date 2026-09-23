import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/model/db/adapters/media_node_drift_adapter.dart';
import 'package:iris/features/media_library/model/db/dao/media_nodes_dao.dart';
import 'package:iris/features/media_library/model/enum/media_node.dart';
import 'package:iris/features/media_library/model/media_lib/media_node.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/migration/v23_migration.dart';

/// Schema v23 contract (SAF uri subproject):
///
/// - `media_nodes` gains a nullable `uri` TEXT column holding the real
///   `content://` document URI of Android SAF rows (NULL for plain rows).
/// - Legacy rows whose `content://` scheme was collapsed to `content:/` by
///   the old canonicalizer are repaired back to `content://...`.
/// - MigrationV23 is re-entrant.
void main() {
  late AppDatabase db;
  late MediaNodesDao dao;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    dao = MediaNodesDao(db);
    await db.customSelect('SELECT 1').get();
  });

  tearDown(() async {
    await db.close();
  });

  Future<Set<String>> mediaNodeColumns() async {
    final rows = await db.customSelect('PRAGMA table_info(media_nodes)').get();
    return rows.map((row) => row.read<String>('name')).toSet();
  }

  const tree =
      'content://com.android.externalstorage.documents/tree/primary%3ADownload';

  test('schemaVersion advanced to 23', () {
    expect(db.schemaVersion, greaterThanOrEqualTo(23));
  });

  test('media_nodes carries the uri column', () async {
    final cols = await mediaNodeColumns();
    expect(cols, contains('uri'));
  });

  test('MigrationV23 is re-entrant (no-op when column already exists)',
      () async {
    await MigrationV23(db).run(db.createMigrator());
    final cols = await mediaNodeColumns();
    expect(cols, contains('uri'));
  });

  test('collapsed content:/ rows are repaired to content://', () async {
    await db.customInsert(
      'INSERT INTO media_nodes '
      '(storage_id, data_scope_id, path, parent_path, node_kind, name) '
      'VALUES (?, ?, ?, ?, ?, ?)',
      variables: [
        Variable.withString('s1'),
        Variable.withString('s1'),
        Variable.withString('content:/com.android.externalstorage.documents'
            '/tree/primary%3ADownload/Movies/a.mp4'),
        Variable.withString('content:/com.android.externalstorage.documents'
            '/tree/primary%3ADownload/Movies'),
        Variable.withString(MediaNodeKind.file.name),
        Variable.withString('a.mp4'),
      ],
    );
    await MigrationV23(db).run(db.createMigrator());
    final row = await db.customSelect(
      'SELECT path, parent_path FROM media_nodes WHERE storage_id = ?',
      variables: [Variable.withString('s1')],
    ).getSingle();
    expect(row.read<String>('path'),
        '$tree/Movies/a.mp4');
    expect(row.read<String>('parent_path'), '$tree/Movies');
  });

  test('junk content: directory chains are removed by the migration',
      () async {
    await db.customInsert(
      'INSERT INTO media_nodes '
      '(storage_id, data_scope_id, path, parent_path, node_kind, name) '
      'VALUES (?, ?, ?, NULL, ?, ?)',
      variables: [
        Variable.withString('s1'),
        Variable.withString('s1'),
        Variable.withString('content:'),
        Variable.withString(MediaNodeKind.directory.name),
        Variable.withString('content:'),
      ],
    );
    await MigrationV23(db).run(db.createMigrator());
    final count = await db.customSelect(
      'SELECT COUNT(*) AS c FROM media_nodes WHERE storage_id = ?',
      variables: [Variable.withString('s1')],
    ).getSingle();
    expect(count.read<int>('c'), 0);
  });

  test('adapter round-trips a SAF uri on file rows', () async {
    await dao.batchUpsert([
      MediaNode.file(
        id: 's1:0',
        storageId: 's1',
        path: [tree, 'Movies', 'a.mp4'],
        name: 'a.mp4',
        mediaType: MediaType.video,
        uri: '$tree/document/42',
      ).toCompanion(),
    ]);
    final row = await dao.getByPath('s1', '$tree/Movies/a.mp4');
    expect(row, isNotNull);
    expect(row!.uri, '$tree/document/42');

    final node = MediaNodeDriftAdapter.fromDb(row);
    final file = node.maybeMap(file: (f) => f, orElse: () => null);
    expect(file!.uri, '$tree/document/42');
  });

  test('rescan upsert without uri does not wipe a stored uri', () async {
    await dao.batchUpsert([
      MediaNode.file(
        id: 's1:0',
        storageId: 's1',
        path: [tree, 'Movies', 'a.mp4'],
        name: 'a.mp4',
        mediaType: MediaType.video,
        uri: '$tree/document/42',
      ).toCompanion(),
    ]);
    // Plain rescan node (no uri) upserts onto the same row.
    await dao.batchUpsert([
      MediaNode.file(
        id: 's1:0',
        storageId: 's1',
        path: [tree, 'Movies', 'a.mp4'],
        name: 'a.mp4',
        mediaType: MediaType.video,
        durationMs: 1000,
      ).toCompanion(),
    ]);
    final row = await dao.getByPath('s1', '$tree/Movies/a.mp4');
    expect(row!.uri, '$tree/document/42');
    expect(row.durationMs, 1000);
  });
}

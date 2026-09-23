import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/migration/v38_migration.dart';

import 'helpers/sqlite3_loader.dart';

/// Schema v38 contract: `media_nodes.path`/`parent_path` become relative to the
/// storage base for plain local storages; remote (`/`) and Android SAF stay
/// absolute.
void main() {
  ensureSqlite3Loaded();

  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> insertStorage({
    required String id,
    required String basePath,
    String? scope,
  }) =>
      db.customInsert(
        'INSERT INTO storages_table (id, type, name, base_path, data_scope_id) '
        'VALUES (?, ?, ?, ?, ?)',
        variables: [
          Variable.withString(id),
          Variable.withInt(1),
          Variable.withString(id),
          Variable.withString(basePath),
          Variable.withString(scope ?? id),
        ],
      );

  Future<void> insertNode({
    required String scope,
    required String path,
    String? parent,
  }) =>
      db.customInsert(
        'INSERT INTO media_nodes '
        '(storage_id, data_scope_id, path, parent_path, name, node_kind) '
        'VALUES (?, ?, ?, ?, ?, ?)',
        variables: [
          Variable.withString(scope),
          Variable.withString(scope),
          Variable.withString(path),
          parent == null
              ? const Variable<String>(null)
              : Variable.withString(parent),
          Variable.withString(path.split('/').last),
          Variable.withString('file'),
        ],
      );

  Future<List<String?>> paths() async {
    final rows = await db
        .customSelect('SELECT path FROM media_nodes ORDER BY id')
        .get();
    return rows.map((r) => r.read<String>('path')).toList();
  }

  test('schemaVersion advanced to 38', () {
    expect(db.schemaVersion, greaterThanOrEqualTo(38));
  });

  test('relativizes a Windows drive storage (path + parent + root)', () async {
    await insertStorage(id: 'sid', basePath: '["D:"]');
    await insertNode(scope: 'sid', path: 'D:/Movies/a.mp4', parent: 'D:/Movies');
    await insertNode(scope: 'sid', path: 'D:/Movies', parent: 'D:');
    await insertNode(scope: 'sid', path: 'D:', parent: null);

    await MigrationV38(db).run(db.createMigrator());

    expect(await paths(), ['Movies/a.mp4', 'Movies', '']);

    final parents = await db
        .customSelect('SELECT parent_path FROM media_nodes ORDER BY id')
        .get();
    expect(parents.map((r) => r.read<String?>('parent_path')).toList(),
        ['Movies', null, null]);
  });

  test('relativizes an Android mount base', () async {
    await insertStorage(id: 'a', basePath: '["/storage/emulated/0"]');
    await insertNode(
        scope: 'a',
        path: 'storage/emulated/0/Movies/a.mp4',
        parent: 'storage/emulated/0/Movies');
    await MigrationV38(db).run(db.createMigrator());
    expect(await paths(), ['Movies/a.mp4']);
  });

  test('leaves a remote root storage absolute', () async {
    await insertStorage(id: 'w', basePath: '["/"]');
    await insertNode(scope: 'w', path: 'Movies/a.mp4', parent: 'Movies');
    await MigrationV38(db).run(db.createMigrator());
    expect(await paths(), ['Movies/a.mp4']);
  });

  test('leaves a SAF storage absolute', () async {
    const tree =
        'content://com.android.externalstorage.documents/tree/primary%3AMovies';
    await insertStorage(id: 'saf', basePath: '["$tree"]');
    await insertNode(scope: 'saf', path: '$tree/a.mp4', parent: tree);
    await MigrationV38(db).run(db.createMigrator());
    expect(await paths(), ['$tree/a.mp4']);
  });

  test('is idempotent (a second run is a no-op)', () async {
    await insertStorage(id: 'sid', basePath: '["D:"]');
    await insertNode(scope: 'sid', path: 'D:/Movies/a.mp4', parent: 'D:/Movies');
    await MigrationV38(db).run(db.createMigrator());
    await MigrationV38(db).run(db.createMigrator());
    expect(await paths(), ['Movies/a.mp4']);
  });
}

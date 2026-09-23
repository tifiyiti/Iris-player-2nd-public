import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/services/path_prefix_remap_service.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';

import 'helpers/sqlite3_loader.dart';

/// `PathPrefixRemapService` must move every stored path that begins with a
/// storage's old base path to its new one — across all eight path tables — while
/// leaving rows outside the prefix (and whole-storage / NULL rows) untouched.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqlite3Loaded();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureStorageChannel, (call) async => null);

  late AppDatabase db;

  setUpAll(() async {
    db = AppDatabase(NativeDatabase.memory());
    await DbModule.init(db);
  });

  tearDownAll(() async {
    await db.close();
  });

  const tables = [
    'media_nodes',
    'scan_states',
    'scan_queue',
    'scenario_sources',
    'scenario_explicit_items',
    'scenario_excludes',
    'video_tag_members',
    'media_lib_sources',
  ];

  setUp(() async {
    for (final t in tables) {
      await db.customStatement('DELETE FROM $t');
    }
  });

  Future<void> ins(String sql, List<String> vars) => db.customInsert(
        sql,
        variables: [for (final v in vars) Variable.withString(v)],
      );

  Future<String?> pathOf(String table, {String where = ''}) async {
    final rows = await db
        .customSelect('SELECT path FROM $table ${where.isEmpty ? '' : 'WHERE $where'}')
        .get();
    return rows.isEmpty ? null : rows.first.read<String>('path');
  }

  test('canRemap rejects same/empty bases', () {
    expect(PathPrefixRemapService.canRemap('D:', 'E:'), isTrue);
    expect(PathPrefixRemapService.canRemap('D:', 'D:'), isFalse);
    expect(PathPrefixRemapService.canRemap('', 'E:'), isFalse);
    expect(PathPrefixRemapService.canRemap('D:', ''), isFalse);
  });

  test('remaps media_nodes path + parent_path, including the root node',
      () async {
    await ins(
      'INSERT INTO media_nodes (storage_id, data_scope_id, path, parent_path, name, node_kind) '
      'VALUES (?,?,?,?,?,?)',
      ['sid', 'sid', 'D:/Movies/a.mp4', 'D:/Movies', 'a.mp4', 'file'],
    );
    await ins(
      'INSERT INTO media_nodes (storage_id, data_scope_id, path, parent_path, name, node_kind) '
      'VALUES (?,?,?,?,?,?)',
      ['sid', 'sid', 'D:/Movies', 'D:', 'Movies', 'directory'],
    );
    await ins(
      'INSERT INTO media_nodes (storage_id, data_scope_id, path, parent_path, name, node_kind) '
      'VALUES (?,?,?,NULL,?,?)',
      ['sid', 'sid', 'D:', 'D:', 'directory'],
    );
    // Outside the prefix — must not move.
    await ins(
      'INSERT INTO media_nodes (storage_id, data_scope_id, path, parent_path, name, node_kind) '
      'VALUES (?,?,?,?,?,?)',
      ['sid', 'sid', 'C:/Other/x.mp4', 'C:/Other', 'x.mp4', 'file'],
    );

    await const PathPrefixRemapService()
        .remap(storageId: 'sid', oldBase: 'D:', newBase: 'E:');

    final file = await db
        .customSelect(
            "SELECT path, parent_path FROM media_nodes WHERE name = 'a.mp4'")
        .getSingle();
    expect(file.read<String>('path'), 'E:/Movies/a.mp4');
    expect(file.read<String>('parent_path'), 'E:/Movies');

    final dir = await db
        .customSelect(
            "SELECT path, parent_path FROM media_nodes WHERE name = 'Movies'")
        .getSingle();
    expect(dir.read<String>('path'), 'E:/Movies');
    expect(dir.read<String>('parent_path'), 'E:');

    final root = await db
        .customSelect(
            "SELECT path, parent_path FROM media_nodes WHERE name = 'D:'")
        .getSingle();
    expect(root.read<String>('path'), 'E:');
    expect(root.read<String?>('parent_path'), isNull);

    expect(
      await pathOf('media_nodes', where: "name = 'x.mp4'"),
      'C:/Other/x.mp4',
    );
  });

  test('remaps the scan tables', () async {
    await ins(
      'INSERT INTO scan_states (storage_id, data_scope_id, path, status) VALUES (?,?,?,?)',
      ['sid', 'sid', 'D:/Movies', '2'],
    );
    await ins(
      'INSERT INTO scan_queue (storage_id, data_scope_id, path, depth) VALUES (?,?,?,?)',
      ['sid', 'sid', 'D:/Movies', '1'],
    );

    await const PathPrefixRemapService()
        .remap(storageId: 'sid', oldBase: 'D:', newBase: 'E:');

    expect(await pathOf('scan_states'), 'E:/Movies');
    expect(await pathOf('scan_queue'), 'E:/Movies');
  });

  test('remaps scenario / tag / library tables and leaves whole-storage rows',
      () async {
    await ins(
      'INSERT INTO scenario_sources (scenario_id, storage_id, path) VALUES (?,?,?)',
      ['sc', 'sid', 'D:/Movies'],
    );
    await ins(
      'INSERT INTO scenario_sources (scenario_id, storage_id, path) VALUES (?,?,?)',
      ['sc', 'sid', ''],
    );
    await ins(
      'INSERT INTO scenario_explicit_items (scenario_id, storage_id, path) VALUES (?,?,?)',
      ['sc', 'sid', 'D:/Movies/a.mp4'],
    );
    await ins(
      'INSERT INTO scenario_excludes (scenario_id, kind, storage_id, path) VALUES (?,?,?,?)',
      ['sc', 'media', 'sid', 'D:/Movies/a.mp4'],
    );
    await ins(
      'INSERT INTO video_tag_members (tag_id, storage_id, path) VALUES (?,?,?)',
      ['1', 'sid', 'D:/Movies/a.mp4'],
    );
    await ins(
      'INSERT INTO media_lib_sources (library_id, storage_id, path) VALUES (?,?,?)',
      ['lib', 'sid', 'D:/Movies'],
    );
    await ins(
      'INSERT INTO media_lib_sources (library_id, storage_id, path) VALUES (?,?,NULL)',
      ['lib', 'sid'],
    );

    await const PathPrefixRemapService()
        .remap(storageId: 'sid', oldBase: 'D:', newBase: 'E:');

    expect(
      await pathOf('scenario_sources', where: "path <> ''"),
      'E:/Movies',
    );
    expect(
      await pathOf('scenario_sources', where: "path = ''"),
      '',
      reason: 'whole-storage source stays empty',
    );
    expect(await pathOf('scenario_explicit_items'), 'E:/Movies/a.mp4');
    expect(await pathOf('scenario_excludes'), 'E:/Movies/a.mp4');
    expect(await pathOf('video_tag_members'), 'E:/Movies/a.mp4');
    expect(await pathOf('media_lib_sources', where: 'path IS NOT NULL'),
        'E:/Movies');
  });

  test('UPDATE OR REPLACE collapses a stale destination row', () async {
    await ins(
      'INSERT INTO media_nodes (storage_id, data_scope_id, path, parent_path, name, node_kind) '
      'VALUES (?,?,?,?,?,?)',
      ['sid', 'sid', 'D:/Movies/a.mp4', 'D:/Movies', 'a.mp4', 'file'],
    );
    await ins(
      'INSERT INTO media_nodes (storage_id, data_scope_id, path, parent_path, name, node_kind) '
      'VALUES (?,?,?,?,?,?)',
      ['sid', 'sid', 'E:/Movies/a.mp4', 'E:/Movies', 'stale.mp4', 'file'],
    );

    await const PathPrefixRemapService()
        .remap(storageId: 'sid', oldBase: 'D:', newBase: 'E:');

    final rows = await db
        .customSelect(
            "SELECT name FROM media_nodes WHERE path = 'E:/Movies/a.mp4'")
        .get();
    expect(rows, hasLength(1));
    expect(rows.single.read<String>('name'), 'a.mp4',
        reason: 'the moved row replaces the stale one');
  });

  test('same base is a no-op', () async {
    await ins(
      'INSERT INTO media_nodes (storage_id, data_scope_id, path, parent_path, name, node_kind) '
      'VALUES (?,?,?,?,?,?)',
      ['sid', 'sid', 'D:/Movies/a.mp4', 'D:/Movies', 'a.mp4', 'file'],
    );
    await const PathPrefixRemapService()
        .remap(storageId: 'sid', oldBase: 'D:', newBase: 'D:');
    expect(await pathOf('media_nodes'), 'D:/Movies/a.mp4');
  });
}

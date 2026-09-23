import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/model/db/adapters/media_node_drift_adapter.dart';
import 'package:iris/features/media_library/model/enum/media_lib_sources.dart';
import 'package:iris/features/media_library/model/enum/media_node.dart';
import 'package:iris/features/media_library/model/media_lib/media_node.dart';
import 'package:iris/features/media_library/search/model/search_exclude_rule.dart';
import 'package:iris/features/scenario_playback/model/enum/exclude_rule_kind.dart';
import 'package:iris/features/scenario_playback/model/enum/exclude_scope.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/models/db/storage_path_codec.dart';
import 'package:iris/utils/path_conv.dart';

import 'helpers/sqlite3_loader.dart';

/// With a base resolver wired, `media_nodes` stores paths RELATIVE to the
/// storage base while every domain consumer still sees the absolute path — so a
/// drive-letter change touches no node rows.
void main() {
  ensureSqlite3Loaded();

  late AppDatabase db;

  setUpAll(() async {
    db = AppDatabase(NativeDatabase.memory());
    await DbModule.init(db);
  });

  tearDownAll(() async {
    await db.close();
  });

  setUp(() async {
    await DbModule.mediaNodesDao
        .delete(DbModule.mediaNodesDao.mediaNodesTable)
        .go();
    StoragePathCodec.baseResolver = (id) => id == 'sid' ? const ['D:'] : null;
  });

  tearDown(() => StoragePathCodec.baseResolver = (_) => null);

  Future<void> insertFile(String absPath) async {
    final segs = pathConv(absPath);
    await DbModule.mediaNodesDao.batchUpsert([
      MediaNode.file(
        id: 'x',
        storageId: 'sid',
        path: segs,
        parentPath:
            segs.length <= 1 ? null : segs.sublist(0, segs.length - 1).join('/'),
        pathDepth: segs.length,
        name: segs.last,
        mediaType: MediaType.video,
        sizeInBytes: 1,
      ).toCompanion(),
    ]);
  }

  Future<List<String>> storedPaths() async {
    final rows = await db.customSelect('SELECT path FROM media_nodes').get();
    return rows.map((r) => r.read<String>('path')).toList();
  }

  test('toCompanion stores the path relative to the base', () async {
    await insertFile('D:/Movies/a.mp4');
    expect(await storedPaths(), ['Movies/a.mp4']);
  });

  test('fromDb rebuilds the absolute path and parent', () async {
    await insertFile('D:/Movies/a.mp4');
    final row = await DbModule.mediaNodesDao.getByPath('sid', 'D:/Movies/a.mp4');
    expect(row, isNotNull);
    final node = MediaNodeDriftAdapter.fromDb(row!);
    expect(node.path.join('/'), 'D:/Movies/a.mp4');
    expect(node.parentPath, 'D:/Movies');
  });

  test('getByPath is idempotent (accepts relative or absolute)', () async {
    await insertFile('D:/Movies/a.mp4');
    expect(await DbModule.mediaNodesDao.getByPath('sid', 'D:/Movies/a.mp4'),
        isNotNull);
    expect(await DbModule.mediaNodesDao.getByPath('sid', 'Movies/a.mp4'),
        isNotNull);
  });

  test('getPagedNodesForSources matches an absolute source path', () async {
    await insertFile('D:/Movies/a.mp4');
    final res = await DbModule.mediaNodeRepo.getPagedNodesForSources(
      sources: [
        (
          storageId: 'sid',
          path: 'D:/Movies',
          kind: MediaSourceKind.directory,
          recursive: true,
          scenarioSourceId: null,
        ),
      ],
      nodeKind: MediaNodeKind.file,
      page: 1,
      pageSize: 10,
    );
    expect(res.totalItems, 1);
  });

  test('an absolute exclude rule prunes the relative row', () async {
    await insertFile('D:/Movies/a.mp4');
    final res = await DbModule.mediaNodeRepo.getPagedNodesForSources(
      sources: [
        (
          storageId: 'sid',
          path: 'D:/Movies',
          kind: MediaSourceKind.directory,
          recursive: true,
          scenarioSourceId: null,
        ),
      ],
      excludeRules: [
        const SearchExcludeRule(
          scope: ExcludeScope.scenario,
          kind: ExcludeRuleKind.media,
          storageId: 'sid',
          path: 'D:/Movies/a.mp4',
        ),
      ],
      nodeKind: MediaNodeKind.file,
      page: 1,
      pageSize: 10,
    );
    expect(res.totalItems, 0);
  });

  test('getExistingFilePaths returns the absolute form', () async {
    await insertFile('D:/Movies/a.mp4');
    final existing = await DbModule.mediaNodeRepo
        .getExistingFilePaths(storageId: 'sid', paths: ['D:/Movies/a.mp4']);
    expect(existing, contains('D:/Movies/a.mp4'));
  });

  test('deleteByPathPrefix accepts the absolute prefix', () async {
    await insertFile('D:/Movies/a.mp4');
    await DbModule.mediaNodesDao.deleteByPathPrefix('sid', 'D:/Movies');
    expect(await DbModule.mediaNodesDao.getByPath('sid', 'D:/Movies/a.mp4'),
        isNull);
  });

  test('a remote storage base leaves paths untouched', () async {
    StoragePathCodec.baseResolver =
        (id) => id == 'webdav' ? const ['/'] : null;
    await DbModule.mediaNodesDao.batchUpsert([
      MediaNode.file(
        id: 'x',
        storageId: 'webdav',
        path: const ['Movies', 'a.mp4'],
        parentPath: 'Movies',
        pathDepth: 2,
        name: 'a.mp4',
        mediaType: MediaType.video,
      ).toCompanion(),
    ]);
    expect(await storedPaths(), ['Movies/a.mp4']);
  });
}

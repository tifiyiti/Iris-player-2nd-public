import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/model/db/dao/media_nodes_dao.dart';
import 'package:iris/features/media_library/model/db/repositories/sub/media_node_repository.dart';
import 'package:iris/features/media_library/model/enum/media_lib_sources.dart';
import 'package:iris/features/media_library/model/enum/media_node.dart';
import 'package:iris/features/media_library/model/media_lib/media_node.dart';
import 'package:iris/features/media_library/services/media_node_sync_service.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/storages/storage.dart';

void main() {
  late AppDatabase db;
  late MediaNodesDao dao;
  late MediaNodeRepository repo;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    dao = MediaNodesDao(db);
    repo = MediaNodeRepository(dao);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> insertNode(MediaNode node) => dao.insertNode(node);

  MediaNode file(String path,
      {MediaType mediaType = MediaType.video}) {
    final segments = path.split('/');
    return MediaNode.file(
      id: 'st1:$path',
      storageId: 'st1',
      path: segments,
      parentPath: segments.length == 1 ? null : segments.sublist(0, segments.length - 1).join('/'),
      pathDepth: segments.length,
      name: segments.last,
      mediaType: mediaType,
    );
  }

  MediaNode dir(String path) {
    final segments = path.split('/');
    return MediaNode.directory(
      id: 'st1:$path',
      storageId: 'st1',
      path: segments,
      parentPath: segments.length == 1 ? null : segments.sublist(0, segments.length - 1).join('/'),
      pathDepth: segments.length,
      name: segments.last,
    );
  }

  group('getPagedNodesForSources hideEmptyDirs (D2)', () {
    const sources = <SourcesQuerySource>[
      (
        storageId: 'st1',
        path: null,
        kind: MediaSourceKind.storage,
        recursive: true,
        scenarioSourceId: null,
      ),
    ];

    setUp(() async {
      // A: playable file directly under it → non-empty.
      await insertNode(dir('A'));
      await insertNode(file('A/v1.mp4', mediaType: MediaType.video));
      // B: playable file only in a subdirectory → non-empty (recursive).
      await insertNode(dir('B'));
      await insertNode(dir('B/Sub'));
      await insertNode(file('B/Sub/a1.mp3', mediaType: MediaType.audio));
      // C: only an unknown-type file row → empty.
      await insertNode(dir('C'));
      await insertNode(file('C/notes.txt', mediaType: MediaType.unknown));
      // D: no children at all → empty.
      await insertNode(dir('D'));
    });

    test('hideEmptyDirs=false (default) returns every directory', () async {
      final result = await repo.getPagedNodesForSources(
        sources: sources,
        nodeKind: MediaNodeKind.directory,
        page: 1,
        pageSize: 100,
      );

      expect(result.totalItems, 5);
      expect(
        result.items.map((e) => e.name),
        containsAll(['A', 'B', 'Sub', 'C', 'D']),
      );
    });

    test('hideEmptyDirs=true keeps dirs with playable descendants (COUNT synced)',
        () async {
      final result = await repo.getPagedNodesForSources(
        sources: sources,
        nodeKind: MediaNodeKind.directory,
        hideEmptyDirs: true,
        page: 1,
        pageSize: 100,
      );

      // A (direct video), B (audio in subtree), B/Sub (direct audio) are
      // non-empty; C (only unknown file) and D (no children) are hidden.
      expect(result.totalItems, 3);
      expect(result.items.map((e) => e.name), containsAll(['A', 'B', 'Sub']));
      expect(result.items.map((e) => e.name), isNot(contains('C')));
      expect(result.items.map((e) => e.name), isNot(contains('D')));
    });

    test('hideEmptyDirs is ignored for non-directory nodeKind (allMedia safe)',
        () async {
      final result = await repo.getPagedNodesForSources(
        sources: sources,
        nodeKind: MediaNodeKind.file,
        mediaTypes: const [MediaType.video, MediaType.audio],
        hideEmptyDirs: true,
        page: 1,
        pageSize: 100,
      );

      expect(result.totalItems, 2); // A/v1.mp4 + B/Sub/a1.mp3
      expect(result.items.map((e) => e.name), containsAll(['v1.mp4', 'a1.mp3']));
      expect(result.items.map((e) => e.name), isNot(contains('notes.txt')));
    });
  });

  group('aggregate recomputation (D2a)', () {
    setUp(() async {
      await insertNode(dir('Movies'));
      await insertNode(file('Movies/a.mp4', mediaType: MediaType.video));
      await insertNode(dir('Movies/Sub'));
      await insertNode(file('Movies/Sub/b.mp3', mediaType: MediaType.audio));
      await insertNode(file('Movies/c.txt', mediaType: MediaType.unknown));
    });

    Future<MediaNodesTableData> nodeAt(String path) async {
      final node = await dao.getByPath('st1', path);
      expect(node, isNotNull, reason: 'expected node at $path');
      return node!;
    }

    test('recomputeDirAggregates computes direct + recursive media (unknown excluded)',
        () async {
      await repo.recomputeDirAggregates(
          storageId: 'st1', dirPath: 'Movies/Sub');
      await repo.recomputeDirAggregates(storageId: 'st1', dirPath: 'Movies');

      final movies = await nodeAt('Movies');
      expect(movies.totalMediaCount, 2); // a.mp4 + Sub/b.mp3
      expect(movies.directMediaCount, 1); // a.mp4 (c.txt unknown excluded)
      expect(movies.totalDirCount, 1);
      expect(movies.directDirCount, 1);
      expect(movies.totalItemCount, 4); // a + Sub + b + c
    });

    test('recomputeDirAncestors walks up to the storage root', () async {
      await repo.recomputeDirAncestors(
          storageId: 'st1', startPath: 'Movies/Sub');

      final sub = await nodeAt('Movies/Sub');
      expect(sub.totalMediaCount, 1); // b.mp3

      final movies = await nodeAt('Movies');
      expect(movies.totalMediaCount, 2); // a.mp4 + Sub
      expect(movies.totalDirCount, 1);
    });

    test('ensureDirNode creates a missing browsed-directory node', () async {
      await insertNode(file('DirX/f.mp4', mediaType: MediaType.video));

      expect(await dao.getByPath('st1', 'DirX'), isNull);

      await repo.ensureDirNode(storageId: 'st1', dirPath: 'DirX');

      final node = await dao.getByPath('st1', 'DirX');
      expect(node, isNotNull);
      expect(node!.nodeKind, MediaNodeKind.directory);
      expect(node.parentPath, isNull);

      // Idempotent.
      await repo.ensureDirNode(storageId: 'st1', dirPath: 'DirX');
      final again = await dao.getByPath('st1', 'DirX');
      expect(again, isNotNull);
    });
  });

  group('D2a leading-slash recompute (files-paged browser paths)', () {
    setUp(() async {
      // Realistic storage-relative paths including the base prefix.
      await insertNode(dir('storage/emulated/0/Movies'));
      await insertNode(
          file('storage/emulated/0/Movies/a.mp4', mediaType: MediaType.video));
      await insertNode(dir('storage/emulated/0/Movies/Sub'));
      await insertNode(
          file('storage/emulated/0/Movies/Sub/b.mp3', mediaType: MediaType.audio));
    });

    test('recomputeDirAncestors resolves a leading-slash startPath', () async {
      // Browser `_currentPath` form: `/storage/emulated/0/Movies/Sub`.
      await repo.recomputeDirAncestors(
        storageId: 'st1',
        startPath: '/storage/emulated/0/Movies/Sub',
      );

      final sub = await dao.getByPath('st1', 'storage/emulated/0/Movies/Sub');
      expect(sub!.totalMediaCount, 1); // b.mp3

      final movies = await dao.getByPath('st1', 'storage/emulated/0/Movies');
      expect(movies!.totalMediaCount, 2); // a.mp4 + Sub
      expect(movies.totalDirCount, 1);
    });

    test('ensureDirNode does not reset aggregates of an existing canonical node',
        () async {
      // Simulate a prior scan that computed aggregates (recompute from Sub
      // walks up: Sub=1, then Movies = a.mp4 + Sub = 2).
      await repo.recomputeDirAncestors(
        storageId: 'st1',
        startPath: 'storage/emulated/0/Movies/Sub',
      );
      final before =
          await dao.getByPath('st1', 'storage/emulated/0/Movies');
      expect(before!.totalMediaCount, 2);

      // Browsing again with the leading-slash browser path must not reset it.
      await repo.ensureDirNode(
        storageId: 'st1',
        dirPath: '/storage/emulated/0/Movies',
      );
      final after = await dao.getByPath('st1', 'storage/emulated/0/Movies');
      expect(after!.totalMediaCount, 2);
      expect(after.nodeKind, MediaNodeKind.directory);
    });
  });

  group('MediaNodeSyncService.syncDirectory', () {
    late Storage storage;

    setUp(() async {
      DbModule.init(db); // service routes through DbModule.
      storage = Storage.local(
        id: 'st1',
        type: StorageType.internal,
        name: 'S',
        basePath: ['/storage/emulated/0'],
      );
    });

    test('populates dirs/files, drops non-media, recomputes aggregates',
        () async {
      final items = [
        FileItem(
          storageId: 'st1',
          storageType: StorageType.internal,
          name: 'Movies',
          uri: '/storage/emulated/0/Movies',
          path: ['/storage/emulated/0', 'Movies'],
          isDir: true,
          type: ContentType.other,
        ),
        FileItem(
          storageId: 'st1',
          storageType: StorageType.internal,
          name: 'v.mp4',
          uri: '/storage/emulated/0/Movies/v.mp4',
          path: ['/storage/emulated/0', 'Movies', 'v.mp4'],
          size: 100,
          type: ContentType.video,
        ),
        FileItem(
          storageId: 'st1',
          storageType: StorageType.internal,
          name: 'notes.txt',
          uri: '/storage/emulated/0/Movies/notes.txt',
          path: ['/storage/emulated/0', 'Movies', 'notes.txt'],
          type: ContentType.other,
        ),
      ];

      await MediaNodeSyncService().syncDirectory(
        storage: storage,
        items: items,
        dirPath: ['storage', 'emulated', '0', 'Movies'],
      );

      final dirRow = await dao.getByPath('st1', 'storage/emulated/0/Movies');
      expect(dirRow, isNotNull);
      expect(dirRow!.nodeKind, MediaNodeKind.directory);
      expect(dirRow.totalMediaCount, 1); // v.mp4 (notes.txt excluded)

      final fileRow =
          await dao.getByPath('st1', 'storage/emulated/0/Movies/v.mp4');
      expect(fileRow, isNotNull);
      expect(fileRow!.mediaType, MediaType.video);
      expect(fileRow.parentPath, 'storage/emulated/0/Movies');

      expect(
        await dao.getByPath('st1', 'storage/emulated/0/Movies/notes.txt'),
        isNull,
      );
    });
  });

  group('repairLegacyPaths', () {
    Future<void> insertLegacy(
      String rawPath, {
      String? parent,
      MediaNodeKind kind = MediaNodeKind.directory,
      MediaType? mediaType,
    }) async {
      final segments = rawPath.split('/').where((s) => s.isNotEmpty).toList();
      await db.into(db.mediaNodesTable).insert(
            MediaNodesTableCompanion.insert(
              storageId: 'st1',
              dataScopeId: drift.Value('st1'),
              path: rawPath,
              name: segments.last,
              normalizedName: drift.Value(segments.last.toLowerCase()),
              nodeKind: kind,
              mediaType: drift.Value(mediaType),
              parentPath: drift.Value(parent),
              pathDepth: drift.Value(segments.length),
            ),
          );
    }

    test('drops legacy duplicates when a canonical row exists', () async {
      // Legacy (pre-canonicalization) file row.
      await insertLegacy(
        '/storage/emulated/0/Movies/v.mp4',
        parent: '/storage/emulated/0/Movies',
        kind: MediaNodeKind.file,
        mediaType: MediaType.video,
      );
      // Canonical row for the same physical file (later sync).
      await insertNode(
          file('storage/emulated/0/Movies/v.mp4', mediaType: MediaType.video));

      await repo.repairLegacyPaths('st1');

      expect(
        await dao.getByPath('st1', 'storage/emulated/0/Movies/v.mp4'),
        isNotNull,
      );
      expect(await dao.getLegacySlashRows('st1'), isEmpty);
    });

    test('rewrites a legacy path to canonical when no canonical row exists',
        () async {
      await insertLegacy('/storage/emulated/0/Movies');
      await insertLegacy(
        '/storage/emulated/0/Movies/v.mp4',
        parent: '/storage/emulated/0/Movies',
        kind: MediaNodeKind.file,
        mediaType: MediaType.video,
      );

      await repo.repairLegacyPaths('st1');

      expect(
        await dao.getByPath('st1', 'storage/emulated/0/Movies'),
        isNotNull,
      );
      expect(
        await dao.getByPath('st1', 'storage/emulated/0/Movies/v.mp4'),
        isNotNull,
      );
      expect(await dao.getLegacySlashRows('st1'), isEmpty);
    });
  });
}

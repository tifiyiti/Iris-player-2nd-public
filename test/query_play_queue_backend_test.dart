import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/model/db/dao/media_nodes_dao.dart';
import 'package:iris/features/media_library/model/db/repositories/sub/media_node_repository.dart';
import 'package:iris/features/media_library/model/media_lib/media_node.dart';
import 'package:iris/features/media_library/play_queue/backends/query_play_queue_backend.dart';
import 'package:iris/features/media_library/play_queue/models/play_queue_source.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';

void main() {
  group('QueryPlayQueueBackend shuffle coverage', () {
    late AppDatabase moduleDb;
    late AppDatabase db;
    late MediaNodeRepository nodeRepo;

    setUpAll(() {
      // DbModule is a one-time singleton; a throwaway in-memory DB is enough
      // (the tests seed and query through their own per-test DB via nodeRepo).
      moduleDb = AppDatabase(NativeDatabase.memory());
      DbModule.init(moduleDb);
    });

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      nodeRepo = MediaNodeRepository(MediaNodesDao(db));
    });

    tearDown(() async {
      await db.close();
    });

    tearDownAll(() async {
      await moduleDb.close();
    });

    Future<void> seedMedia(List<String> names) async {
      final dao = MediaNodesDao(db);
      for (final name in names) {
        await dao.insertNode(MediaNode.file(
          id: name,
          storageId: 'st1',
          path: ['A', name],
          name: name,
          mediaType: MediaType.video,
        ));
      }
    }

    Future<List<String>> collectAll(QueryPlayQueueBackend backend) async {
      final seen = <String>[];
      var page = 1;
      while (seen.length < backend.totalCount) {
        final items = await backend.getPagedQueueItems(
            page: page, pageSize: 2, mediaType: MediaType.video);
        if (items.isEmpty) break;
        seen.addAll(items.map((it) => it.file.name));
        page++;
      }
      return seen;
    }

    test('shuffled pages cover every media exactly once (N=5, old broken size)',
        () async {
      const names = ['a.mp4', 'b.mp4', 'c.mp4', 'd.mp4', 'e.mp4'];
      await seedMedia(names);

      final backend = QueryPlayQueueBackend(nodeRepo: nodeRepo, scopedMediaTypes: () => null);
      await backend.initialized;

      await backend.setSource(
        PlayQueueSource.folder(
          storageId: 'st1',
          parentPath: 'A',
          mediaType: MediaType.video,
          recursive: true,
        ),
      );
      expect(backend.totalCount, 5);

      // shuffle() uses inverse(currentOriginalPos) to keep the playing item;
      // the result must stay in bounds for the new permutation.
      await backend.shuffle();
      expect(backend.totalCount, 5);
      expect(backend.currentVirtualPos, inInclusiveRange(0, 4));

      final seen = await collectAll(backend);
      expect(seen.length, 5);
      expect(seen.toSet(), names.toSet());
      await backend.dispose();
    });

    test('shuffled pages cover every media exactly once (N=8, old broken size)',
        () async {
      final names = [for (var i = 1; i <= 8; i++) 'f$i.mp4'];
      await seedMedia(names);

      final backend = QueryPlayQueueBackend(nodeRepo: nodeRepo, scopedMediaTypes: () => null);
      await backend.initialized;

      await backend.setSource(
        PlayQueueSource.folder(
          storageId: 'st1',
          parentPath: 'A',
          mediaType: MediaType.video,
          recursive: true,
        ),
      );
      expect(backend.totalCount, 8);

      await backend.shuffle();
      final seen = await collectAll(backend);
      expect(seen.length, 8);
      expect(seen.toSet(), names.toSet());
      await backend.dispose();
    });

    test('update with an empty queue does not throw', () async {
      // Regression: (index ?? 0).clamp(0, length - 1) is clamp(0, -1) on an
      // empty list, which num.clamp rejects with ArgumentError.
      final backend = QueryPlayQueueBackend(nodeRepo: nodeRepo, scopedMediaTypes: () => null);
      await backend.initialized;

      await backend.update(playQueue: const []);
      expect(backend.totalCount, 0);
      expect(backend.currentVirtualPos, 0);
      await backend.dispose();
    });
  });
}

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/model/db/dao/media_nodes_dao.dart';
import 'package:iris/features/media_library/model/db/repositories/sub/media_node_repository.dart';
import 'package:iris/features/media_library/model/media_lib/media_node.dart';
import 'package:iris/features/media_library/play_queue/backends/query_play_queue_backend.dart';
import 'package:iris/features/media_library/play_queue/models/play_queue_source.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/store/use_app_store.dart';

/// Browse-media-scope wiring for QueryPlayQueueBackend: count and fetch must
/// stay consistent with each other AND honor the resolved scope. The
/// non-recursive folder count additionally drops its legacy "all children"
/// (directories included) semantics to match the files-only fetch.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureStorageChannel, (call) async => null);

  setUpAll(() async {
    await DbModule.init(AppDatabase(NativeDatabase.memory()));
    useAppStore();
    await useAppStore().initialized;
  });

  tearDown(() async {
    final store = useAppStore();
    store.set(store.state.copyWith(
      browseMediaScope: BrowseMediaScope.all,
      useMetadataSettings: false,
    ));
  });

  group('QueryPlayQueueBackend honors browse scope', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      final dao = MediaNodesDao(db);
      Future<void> file(String path, MediaType mediaType) async {
        final segments = path.split('/');
        await dao.insertNode(MediaNode.file(
          id: 'st-qb:$path',
          storageId: 'st-qb',
          path: segments,
          parentPath:
              segments.sublist(0, segments.length - 1).join('/'),
          pathDepth: segments.length,
          name: segments.last,
          mediaType: mediaType,
        ));
      }

      Future<void> dir(String path) async {
        final segments = path.split('/');
        await dao.insertNode(MediaNode.directory(
          id: 'st-qb:$path',
          storageId: 'st-qb',
          path: segments,
          parentPath: segments.length == 1
              ? null
              : segments.sublist(0, segments.length - 1).join('/'),
          pathDepth: segments.length,
          name: segments.last,
        ));
      }

      // D holds one video, one audio, and a subdirectory (with its own file)
      // so the legacy all-children count diverges from the files-only fetch.
      await dir('D');
      await file('D/v.mp4', MediaType.video);
      await file('D/a.mp3', MediaType.audio);
      await dir('D/Sub');
      await file('D/Sub/v2.mp4', MediaType.video);
    });

    tearDown(() => db.close());

    Future<int> totalCountFor(PlayQueueSource source) async {
      final backend = QueryPlayQueueBackend(
        nodeRepo: MediaNodeRepository(MediaNodesDao(db)),
      );
      await backend.initialized;
      await backend.setSource(source);
      return backend.totalCount;
    }

    test('non-recursive folder count matches files-only fetch when gate OFF',
        () async {
      await useAppStore().setMetadataGate(false);
      expect(
        await totalCountFor(const PlayQueueSource.folder(
          storageId: 'st-qb',
          parentPath: 'D',
          recursive: false,
        )),
        2,
        reason: 'v.mp4 + a.mp3 — Sub must not be counted',
      );
    });

    test('videoOnly narrows non-recursive folder count', () async {
      await useAppStore().setMetadataGate(true);
      await useAppStore().updateBrowseMediaScope(BrowseMediaScope.videoOnly);
      expect(
        await totalCountFor(const PlayQueueSource.folder(
          storageId: 'st-qb',
          parentPath: 'D',
          recursive: false,
        )),
        1,
      );
    });

    test('recursive folder count honors videoOnly across subtree', () async {
      await useAppStore().setMetadataGate(true);
      await useAppStore().updateBrowseMediaScope(BrowseMediaScope.videoOnly);
      expect(
        await totalCountFor(const PlayQueueSource.folder(
          storageId: 'st-qb',
          parentPath: 'D',
          recursive: true,
        )),
        2,
      );
    });

    test('allMedia source count honors audioOnly', () async {
      await useAppStore().setMetadataGate(true);
      await useAppStore().updateBrowseMediaScope(BrowseMediaScope.audioOnly);
      expect(
        await totalCountFor(const PlayQueueSource.allMedia(storageId: 'st-qb')),
        1,
      );
    });
  });
}

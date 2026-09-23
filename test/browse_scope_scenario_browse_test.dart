import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/model/media_lib/media_node.dart';
import 'package:iris/features/scenario_playback/view/browse/paged_scenario_browse_data_source.dart';
import 'package:iris/features/scenario_playback/store/use_playback_scenario_store.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_play_queue_store.dart';
import 'package:iris/store/use_storage_store.dart';

/// Browse-media-scope wiring for the scenario browse page: directory listings
/// (mixed dirs+files) honor the scope — directories without in-scope
/// descendants become invisible while in-scope ones stay navigable.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureStorageChannel, (call) async => null);

  setUpAll(() async {
    await DbModule.init(AppDatabase(NativeDatabase.memory()));
    usePlaybackScenarioStore();
    await usePlaybackScenarioStore().initialized;
    await runZonedGuarded(() async {
      usePlayQueueStore();
      await usePlayQueueStore().initialized;
      useAppStore();
      await useAppStore().initialized;
      useStorageStore();
      await useStorageStore().initialized;
    }, (Object e, StackTrace st) {});
  });

  tearDown(() async {
    final store = useAppStore();
    store.set(store.state.copyWith(
      browseMediaScope: BrowseMediaScope.all,
      useMetadataSettings: false,
    ));
  });

  group('PagedScenarioBrowseDataSource honors browse scope', () {
    setUp(() async {
      final dao = DbModule.mediaNodesDao;
      Future<void> file(String path, MediaType mediaType) async {
        final segments = path.split('/');
        await dao.deleteNode('st-sb', path);
        await dao.insertNode(MediaNode.file(
          id: 'st-sb:$path',
          storageId: 'st-sb',
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
        await dao.deleteNode('st-sb', path);
        await dao.insertNode(MediaNode.directory(
          id: 'st-sb:$path',
          storageId: 'st-sb',
          path: segments,
          parentPath: null,
          pathDepth: segments.length,
          name: segments.last,
        ));
      }

      await dir('VidDir');
      await file('VidDir/v.mp4', MediaType.video);
      await dir('AudDir');
      await file('AudDir/a.mp3', MediaType.audio);
    });

    Future<Set<String>> browseRootNames() async {
      final ds = PagedScenarioBrowseDataSource(
        scenarioId: 'sc-sb',
        initialStorageId: 'st-sb',
        // Null keeps the listing at the storage root (empty string would
        // query parentPath == '' and match nothing).
        initialPath: null,
      );
      addTearDown(ds.dispose);
      await pumpEventQueue();
      return ds.items.map((i) => i.name).toSet();
    }

    test('videoOnly keeps video-bearing dirs visible at the root', () async {
      await useAppStore().setMetadataGate(true);
      await useAppStore().updateBrowseMediaScope(BrowseMediaScope.videoOnly);

      expect(await browseRootNames(), {'VidDir'});
    });

    test('gate OFF keeps every directory (legacy)', () async {
      await useAppStore().setMetadataGate(false);

      expect(await browseRootNames(), {'VidDir', 'AudDir'});
    });
  });
}

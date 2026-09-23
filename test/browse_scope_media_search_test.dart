import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/model/enum/media_lib_sources.dart';
import 'package:iris/features/media_library/model/media_lib/media_node.dart';
import 'package:iris/features/media_library/search/data_source/media_search_data_source.dart';
import 'package:iris/features/media_library/search/model/search_context.dart';
import 'package:iris/features/media_library/search/model/search_scope.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/store/use_app_store.dart';

/// Browse-media-scope wiring for the media search data source: both DB query
/// paths (initial run + window refetch) must pass the scoped mediaTypes so
/// out-of-scope files never surface in results.
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

  group('MediaSearchDataSource honors browse scope', () {
    setUp(() async {
      final dao = DbModule.mediaNodesDao;
      await dao.deleteNode('st-sr', 'media-video.mp4');
      await dao.deleteNode('st-sr', 'media-audio.mp3');
      Future<void> file(String path, MediaType mediaType) async {
        final segments = path.split('/');
        await dao.insertNode(MediaNode.file(
          id: 'st-sr:$path',
          storageId: 'st-sr',
          path: segments,
          name: segments.last,
          mediaType: mediaType,
        ));
      }

      await file('media-video.mp4', MediaType.video);
      await file('media-audio.mp3', MediaType.audio);
    });

    MediaSearchDataSource dataSource() => MediaSearchDataSource(
          searchContext: const SearchContext(
            entryContext: SearchEntryContext.scenarioSourcesRoot,
            storageId: 'st-sr',
            sources: [
              SearchSource(
                storageId: 'st-sr',
                kind: MediaSourceKind.storage,
                recursive: true,
              ),
            ],
          ),
        );

    test('videoOnly filters search results', () async {
      await useAppStore().setMetadataGate(true);
      await useAppStore().updateBrowseMediaScope(BrowseMediaScope.videoOnly);

      final ds = dataSource();
      addTearDown(ds.dispose);
      await ds.submitQuery('media');
      expect(ds.items.map((i) => i.name).toSet(), {'media-video.mp4'});
    });

    test('gate OFF keeps both kinds in results', () async {
      await useAppStore().setMetadataGate(false);

      final ds = dataSource();
      addTearDown(ds.dispose);
      await ds.submitQuery('media');
      expect(
          ds.items.map((i) => i.name).toSet(),
          {'media-video.mp4', 'media-audio.mp3'});
    });
  });
}

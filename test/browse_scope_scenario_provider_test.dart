import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/model/db/dao/media_nodes_dao.dart';
import 'package:iris/features/media_library/model/db/repositories/sub/media_node_repository.dart';
import 'package:iris/features/media_library/model/enum/basic_enum.dart';
import 'package:iris/features/media_library/model/media_lib/media_node.dart';
import 'package:iris/features/scenario_playback/model/domain/scenario_source.dart';
import 'package:iris/features/scenario_playback/model/enum/scenario_sort_field.dart';
import 'package:iris/features/scenario_playback/resolver/scenario_source_provider.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/store/use_app_store.dart';

/// Browse-media-scope wiring for the scenario folder source provider: the
/// provider's count/fetch queries must honor the resolved scope while staying
/// consistent with each other (count == fetchable items).
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

  group('FolderSourceProvider honors browse scope', () {
    late AppDatabase db;
    late MediaNodeRepository repo;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      repo = MediaNodeRepository(MediaNodesDao(db));

      Future<void> file(String path, MediaType mediaType) async {
        final segments = path.split('/');
        await MediaNodesDao(db).insertNode(MediaNode.file(
          id: 'st-fsp:$path',
          storageId: 'st-fsp',
          path: segments,
          parentPath: segments.length == 1
              ? null
              : segments.sublist(0, segments.length - 1).join('/'),
          pathDepth: segments.length,
          name: segments.last,
          mediaType: mediaType,
        ));
      }

      await file('v1.mp4', MediaType.video);
      await file('a1.mp3', MediaType.audio);
    });

    tearDown(() => db.close());

    const source = ScenarioSource(
      id: 1,
      scenarioId: 'sc-fsp',
      storageId: 'st-fsp',
      path: '',
      recursive: true,
      sortOrder: 0,
    );

    test('gate ON + videoOnly scopes fetch and count consistently', () async {
      await useAppStore().setMetadataGate(true);
      await useAppStore().updateBrowseMediaScope(BrowseMediaScope.videoOnly);

      const provider = FolderSourceProvider();
      expect(await provider.count(source, repo), 1);
      final items = await provider.fetch(
        source,
        repo,
        offset: 0,
        count: 10,
        sortField: ScenarioSortField.name,
        sortDirection: SortDirection.asc,
        sourceInternalFirst: false,
      );
      expect(items.map((n) => n.name), ['v1.mp4']);
    });

    test('gate OFF keeps the legacy playable-only semantics', () async {
      await useAppStore().setMetadataGate(false);

      const provider = FolderSourceProvider();
      expect(await provider.count(source, repo), 2);
    });
  });
}

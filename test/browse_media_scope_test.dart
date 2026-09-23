import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/model/db/adapters/media_library.dart';
import 'package:iris/features/media_library/model/db/dao/for_page/media_node_page_query.dart';
import 'package:iris/features/media_library/model/db/dao/media_nodes_dao.dart';
import 'package:iris/features/media_library/model/db/repositories/sub/media_node_repository.dart';
import 'package:iris/features/media_library/model/enum/media_lib_sources.dart';
import 'package:iris/features/media_library/model/enum/media_node.dart';
import 'package:iris/features/media_library/model/media_lib/media_library.dart';
import 'package:iris/features/media_library/model/media_lib/media_library_source.dart';
import 'package:iris/features/media_library/model/media_lib/media_node.dart';
import 'package:iris/features/meta_settings/engine/browse_media_scope.dart';
import 'package:iris/features/meta_settings/meta_settings_module.dart';
import 'package:iris/features/media_library/view/content/model/media_lib_content_mode.dart';
import 'package:iris/features/media_library/view/content/store/use_media_lib_content_store.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/store/use_app_store.dart';

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

  group('resolveBrowseMediaScope', () {
    test('gate OFF degrades to all regardless of stored value', () {
      const state = AppState(
        useMetadataSettings: false,
        browseMediaScope: BrowseMediaScope.audioOnly,
      );
      expect(
        resolveBrowseMediaScope(state, metadataEnabled: false),
        BrowseMediaScope.all,
      );
    });

    test('gate ON returns the stored value', () {
      const state = AppState(
        useMetadataSettings: true,
        browseMediaScope: BrowseMediaScope.videoOnly,
      );
      expect(
        resolveBrowseMediaScope(state, metadataEnabled: true),
        BrowseMediaScope.videoOnly,
      );
    });
  });

  group('scopeMediaTypes', () {
    test('all → null (no SQL filter)', () {
      expect(scopeMediaTypes(BrowseMediaScope.all), isNull);
    });

    test('videoOnly / audioOnly → single-element lists', () {
      expect(scopeMediaTypes(BrowseMediaScope.videoOnly), [MediaType.video]);
      expect(scopeMediaTypes(BrowseMediaScope.audioOnly), [MediaType.audio]);
    });
  });

  group('FileItem.matchesBrowseScope', () {
    final video = const FileItem(
      name: 'a.mp4',
      uri: 'file:///x/a.mp4',
      path: ['x', 'a.mp4'],
      type: ContentType.video,
    );
    final audio = const FileItem(
      name: 'b.mp3',
      uri: 'file:///x/b.mp3',
      path: ['x', 'b.mp3'],
      type: ContentType.audio,
    );
    final dir = const FileItem(
        name: 'sub', uri: 'file:///x/sub/', path: ['x', 'sub'], isDir: true);

    test('directories always pass', () {
      expect(dir.matchesBrowseScope(BrowseMediaScope.videoOnly), isTrue);
      expect(dir.matchesBrowseScope(BrowseMediaScope.audioOnly), isTrue);
    });

    test('video passes only under all/videoOnly', () {
      expect(video.matchesBrowseScope(BrowseMediaScope.all), isTrue);
      expect(video.matchesBrowseScope(BrowseMediaScope.videoOnly), isTrue);
      expect(video.matchesBrowseScope(BrowseMediaScope.audioOnly), isFalse);
    });

    test('audio passes only under all/audioOnly', () {
      expect(audio.matchesBrowseScope(BrowseMediaScope.all), isTrue);
      expect(audio.matchesBrowseScope(BrowseMediaScope.audioOnly), isTrue);
      expect(audio.matchesBrowseScope(BrowseMediaScope.videoOnly), isFalse);
    });
  });

  group('browse.mediaScope AUX row persistence', () {
    test('updateBrowseMediaScope writes the row when gate ON+ready',
        () async {
      final store = useAppStore();
      await store.setMetadataGate(true);
      addTearDown(() async {});
      await store.updateBrowseMediaScope(BrowseMediaScope.audioOnly);

      final rows = await MetaSettingsModule.repo.loadRawValues();
      expect(rows['browse.mediaScope'], 'audioOnly');
    });

    test('applyBrowseRows rehydrates when gate ON, degrades when OFF',
        () async {
      await MetaSettingsModule.persistAuxRow('browse.mediaScope', 'videoOnly');

      final on = await useAppStore()
          .applyBrowseRows(const AppState(useMetadataSettings: true));
      expect(on.browseMediaScope, BrowseMediaScope.videoOnly);

      final off = await useAppStore()
          .applyBrowseRows(const AppState(useMetadataSettings: false));
      expect(off.browseMediaScope, BrowseMediaScope.all);
    });

    test('malformed row degrades to base value', () async {
      await MetaSettingsModule.persistAuxRow('browse.mediaScope', 'bogus');
      final s = await useAppStore()
          .applyBrowseRows(const AppState(useMetadataSettings: true));
      expect(s.browseMediaScope, BrowseMediaScope.all);
    });
  });

  group('directory visibility honors scoped mediaTypes (hideEmptyDirs)', () {
    late AppDatabase db;
    late MediaNodesDao dao;
    late MediaNodeRepository repo;

    const sources = <SourcesQuerySource>[
      (
        storageId: 'st-scope',
        path: null,
        kind: MediaSourceKind.storage,
        recursive: true,
        scenarioSourceId: null,
      ),
    ];

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      dao = MediaNodesDao(db);
      repo = MediaNodeRepository(dao);

      MediaNode file(String path, MediaType mediaType) {
        final segments = path.split('/');
        return MediaNode.file(
          id: 'st-scope:$path',
          storageId: 'st-scope',
          path: segments,
          parentPath: segments.sublist(0, segments.length - 1).join('/'),
          pathDepth: segments.length,
          name: segments.last,
          mediaType: mediaType,
        );
      }

      MediaNode dir(String path) {
        final segments = path.split('/');
        return MediaNode.directory(
          id: 'st-scope:$path',
          storageId: 'st-scope',
          path: segments,
          parentPath: segments.length == 1
              ? null
              : segments.sublist(0, segments.length - 1).join('/'),
          pathDepth: segments.length,
          name: segments.last,
        );
      }

      // AudOnly ← mp3 only; VidOnly ← mp4 only.
      await dao.insertNode(dir('AudOnly'));
      await dao.insertNode(file('AudOnly/a.mp3', MediaType.audio));
      await dao.insertNode(dir('VidOnly'));
      await dao.insertNode(file('VidOnly/v.mp4', MediaType.video));
    });

    tearDown(() => db.close());

    test('videoOnly hides audio-only directories', () async {
      final scoped = await repo.getPagedNodesForSources(
        sources: sources,
        nodeKind: MediaNodeKind.directory,
        hideEmptyDirs: true,
        mediaTypes: const [MediaType.video],
        page: 1,
      );
      final names = scoped.items.map((n) => n.name).toSet();
      expect(names.contains('VidOnly'), isTrue,
          reason: 'has a video descendant');
      expect(names.contains('AudOnly'), isFalse,
          reason: 'audio descendants are out of scope');
    });

      test('unscoped default keeps both (legacy semantics unchanged)', () async {
        final plain = await repo.getPagedNodesForSources(
          sources: sources,
          nodeKind: MediaNodeKind.directory,
          hideEmptyDirs: true,
          page: 1,
        );
        expect(plain.items.map((n) => n.name).toSet(),
            containsAll(['VidOnly', 'AudOnly']));
      });
    });

  group('getPagedNodes scoped mediaTypes keep directories visible', () {
    late AppDatabase db;
    late MediaNodesDao dao;
    late MediaNodeRepository repo;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      dao = MediaNodesDao(db);
      repo = MediaNodeRepository(dao);

      MediaNode file(String path, MediaType mediaType) {
        final segments = path.split('/');
        return MediaNode.file(
          id: 'st-pn:$path',
          storageId: 'st-pn',
          path: segments,
          // Production sync writes null for storage-root files
          // (media_node_sync_service.dart:66).
          parentPath: segments.length == 1
              ? null
              : segments.sublist(0, segments.length - 1).join('/'),
          pathDepth: segments.length,
          name: segments.last,
          mediaType: mediaType,
        );
      }

      MediaNode dir(String path) {
        final segments = path.split('/');
        return MediaNode.directory(
          id: 'st-pn:$path',
          storageId: 'st-pn',
          path: segments,
          parentPath: segments.length == 1
              ? null
              : segments.sublist(0, segments.length - 1).join('/'),
          pathDepth: segments.length,
          name: segments.last,
        );
      }

      // Root-level mixed listing: two dirs with opposite-scope subtrees plus
      // one root file of each kind.
      await dao.insertNode(dir('AudOnly'));
      await dao.insertNode(file('AudOnly/a.mp3', MediaType.audio));
      await dao.insertNode(dir('VidOnly'));
      await dao.insertNode(file('VidOnly/v.mp4', MediaType.video));
      await dao.insertNode(file('root-a.mp3', MediaType.audio));
      await dao.insertNode(file('root-v.mp4', MediaType.video));
    });

    tearDown(() => db.close());

    test('mixed listing keeps in-scope dirs and drops out-of-scope rows',
        () async {
      final result = await repo.getDirectoryChildren(
        storageId: 'st-pn',
        parentPath: null,
        page: 1,
        mediaTypes: const [MediaType.video],
      );
      final names = result.items.map((n) => n.name).toSet();
      expect(names, containsAll(['VidOnly', 'root-v.mp4']));
      expect(names, isNot(contains('AudOnly')),
          reason: 'audio-only dir has no video descendant');
      expect(names, isNot(contains('root-a.mp3')));
    });

    test('directory-only query uses EXISTS instead of IN', () async {
      final query = MediaNodePageQuery(
        page: 1,
        pageSize: 100,
        storageId: 'st-pn',
        parentPath: null,
        nodeKind: MediaNodeKind.directory,
        mediaTypes: const [MediaType.audio],
      );
      final result = await repo.getPagedNodes(query);
      expect(result.items.map((n) => n.name), ['AudOnly']);
    });

    test('file-only query keeps plain IN semantics', () async {
      final query = MediaNodePageQuery(
        page: 1,
        pageSize: 100,
        storageId: 'st-pn',
        parentPath: null,
        nodeKind: MediaNodeKind.file,
        mediaTypes: const [MediaType.audio],
      );
      final result = await repo.getPagedNodes(query);
      expect(result.items.map((n) => n.name).toSet(), {'root-a.mp3'});
    });

    test('null mediaTypes keeps the unscoped legacy behavior', () async {
      final result = await repo.getDirectoryChildren(
        storageId: 'st-pn',
        parentPath: null,
        page: 1,
      );
      expect(result.totalItems, 4);
    });

    test('countByMediaTypeUnderPath honors scoped types', () async {
      final all = await dao.countByMediaTypeUnderPath('st-pn', '');
      final scoped = await dao.countByMediaTypeUnderPath(
        'st-pn',
        '',
        mediaTypes: const [MediaType.audio],
      );
      expect(all[MediaType.video], 1);
      expect(all[MediaType.audio], 1);
      expect(scoped.containsKey(MediaType.video), isFalse,
          reason: 'video rows are out of the audio scope');
      expect(scoped[MediaType.audio], 1);
    });
  });

  group('content page store honors browse scope', () {
    setUpAll(() async {
      useMediaLibContentStore();
      await useMediaLibContentStore().initialized;
    });

    /// Each test seeds its own storage+library (unique suffix) because the
    /// module DB is shared for the whole file and node ids are primary keys.
    Future<({String storageId, String libraryId})> seed(String suffix) async {
      final storageId = 'st-cs-$suffix';
      final libraryId = 'sys_cs_$suffix';
      final now = DateTime.now();
      await DbModule.mediaLibsDao.upsert(MediaLibrary(
        id: libraryId,
        name: libraryId,
        type: MediaLibraryType.system,
        createdAt: now,
        updatedAt: now,
      ).toCompanion());
      await DbModule.mediaLibSourcesDao.upsertSource(MediaLibrarySource(
        id: 0,
        libraryId: libraryId,
        storageId: storageId,
        path: null,
      ));

      Future<void> file(String path, MediaType mediaType) async {
        final segments = path.split('/');
        await DbModule.mediaNodesDao.insertNode(MediaNode.file(
          id: '$storageId:$path',
          storageId: storageId,
          path: segments,
          parentPath: segments.length == 1
              ? null
              : segments.sublist(0, segments.length - 1).join('/'),
          pathDepth: segments.length,
          name: segments.last,
          mediaType: mediaType,
        ));
      }

      Future<void> dir(String path) async {
        final segments = path.split('/');
        await DbModule.mediaNodesDao.insertNode(MediaNode.directory(
          id: '$storageId:$path',
          storageId: storageId,
          path: segments,
          parentPath: segments.length == 1
              ? null
              : segments.sublist(0, segments.length - 1).join('/'),
          pathDepth: segments.length,
          name: segments.last,
        ));
      }

      await dir('VidOnly');
      await file('VidOnly/v.mp4', MediaType.video);
      await dir('AudOnly');
      await file('AudOnly/a.mp3', MediaType.audio);
      return (storageId: storageId, libraryId: libraryId);
    }

    Future<Set<String>> refreshTitles(
      String storageId,
      String libraryId,
      MediaLibContentMode mode,
    ) async {
      final s = useMediaLibContentStore();
      s.set(s.state.copyWith(
        currentLibraryId: libraryId,
        currentStorageId:
            mode == MediaLibContentMode.pathTree ? storageId : null,
        currentParentPath: null,
        viewMode: mode,
        requestedPage: 0,
      ));
      await s.refresh();
      return s.runtime.items.map((i) => i.title).toSet();
    }

    /// Seeds a non-playable file row (MediaType.unknown) alongside the
    /// standard VidOnly/AudOnly tree.
    Future<({String storageId, String libraryId})> seedWithJunk(
        String suffix) async {
      final seeded = await seed(suffix);
      final segments = ['junk.txt'];
      await DbModule.mediaNodesDao.insertNode(MediaNode.file(
        id: '${seeded.storageId}:junk.txt',
        storageId: seeded.storageId,
        path: segments,
        parentPath: null,
        pathDepth: 1,
        name: 'junk.txt',
        mediaType: MediaType.unknown,
      ));
      return seeded;
    }

    test('allMedia keeps legacy playable-only baseline when gate OFF',
        () async {
      final seeded = await seedWithJunk('t4');
      await useAppStore().setMetadataGate(false);

      final titles = await refreshTitles(seeded.storageId, seeded.libraryId,
          MediaLibContentMode.allMedia);
      expect(titles, containsAll(['v.mp4', 'a.mp3']));
      expect(titles, isNot(contains('junk.txt')),
          reason: 'legacy [video,audio] baseline must survive scope=all');
    });

    test('allMedia keeps playable-only baseline under gate ON + all',
        () async {
      final seeded = await seedWithJunk('t5');
      await useAppStore().setMetadataGate(true);
      await useAppStore().updateBrowseMediaScope(BrowseMediaScope.all);

      final titles = await refreshTitles(seeded.storageId, seeded.libraryId,
          MediaLibContentMode.allMedia);
      expect(titles, isNot(contains('junk.txt')));
    });

    /// Seeds a directory whose PERSISTED aggregates claim 5 medias / 5000 B /
    /// 5000 ms, while its actual scoped subtree holds one video only
    /// (100 B / 100 ms) plus one audio file.
    Future<({String storageId, String libraryId})> seedStaleAggregates(
        String suffix) async {
      final seeded = await seed(suffix);
      final dao = DbModule.mediaNodesDao;
      const dirPath = 'BigDir';
      await dao.insertNode(MediaNode.directory(
        id: '${seeded.storageId}:$dirPath',
        storageId: seeded.storageId,
        path: [dirPath],
        parentPath: null,
        pathDepth: 1,
        name: dirPath,
        directMediaCount: 2,
        totalMediaCount: 5,
        totalDirCount: 1,
        totalSizeInBytes: 5000,
        totalDurationMs: 5000,
      ));
      Future<void> file(String name, MediaType mt, int size, int dur) async {
        final p = '$dirPath/$name';
        await dao.insertNode(MediaNode.file(
          id: '${seeded.storageId}:$p',
          storageId: seeded.storageId,
          path: p.split('/'),
          parentPath: dirPath,
          pathDepth: 2,
          name: name,
          mediaType: mt,
          sizeInBytes: size,
          durationMs: dur,
        ));
      }

      await file('v.mp4', MediaType.video, 100, 100);
      await file('a.mp3', MediaType.audio, 200, 200);
      return seeded;
    }

    test('videoOnly overrides dir aggregates in the display list', () async {
      final seeded = await seedStaleAggregates('t6');
      await useAppStore().setMetadataGate(true);
      await useAppStore().updateBrowseMediaScope(BrowseMediaScope.videoOnly);

      final s = useMediaLibContentStore();
      s.set(s.state.copyWith(
        currentLibraryId: seeded.libraryId,
        currentStorageId: seeded.storageId,
        currentParentPath: null,
        viewMode: MediaLibContentMode.pathTree,
        requestedPage: 0,
      ));
      await s.refresh();

      final big = s.runtime.items.firstWhere((i) => i.title == 'BigDir');
      expect(big.mediaCount, 1,
          reason: 'only the video descendant is in scope');
      expect(big.subtitle, contains('100.00 B'),
          reason: 'size overridden to the scoped sum');
    });

    test('gate OFF keeps the persisted aggregates untouched', () async {
      final seeded = await seedStaleAggregates('t7');
      await useAppStore().setMetadataGate(false);

      final s = useMediaLibContentStore();
      s.set(s.state.copyWith(
        currentLibraryId: seeded.libraryId,
        currentStorageId: seeded.storageId,
        currentParentPath: null,
        viewMode: MediaLibContentMode.pathTree,
        requestedPage: 0,
      ));
      await s.refresh();

      final big = s.runtime.items.firstWhere((i) => i.title == 'BigDir');
      expect(big.mediaCount, 5);
    });

    test('allMedia view filters to video under gate ON + videoOnly', () async {
      final seeded = await seed('t1');
      await useAppStore().setMetadataGate(true);
      await useAppStore().updateBrowseMediaScope(BrowseMediaScope.videoOnly);

      expect(
        await refreshTitles(seeded.storageId, seeded.libraryId,
            MediaLibContentMode.allMedia),
        {'v.mp4'},
      );
    });

    test('allMedia view keeps both files when gate OFF (legacy degrade)',
        () async {
      final seeded = await seed('t2');
      await useAppStore().setMetadataGate(false);

      expect(
        await refreshTitles(seeded.storageId, seeded.libraryId,
            MediaLibContentMode.allMedia),
        containsAll(['v.mp4', 'a.mp3']),
      );
    });

    test('pathTree mixed listing keeps only in-scope dirs under videoOnly',
        () async {
      final seeded = await seed('t3');
      await useAppStore().setMetadataGate(true);
      await useAppStore().updateBrowseMediaScope(BrowseMediaScope.videoOnly);

      expect(
        await refreshTitles(seeded.storageId, seeded.libraryId,
            MediaLibContentMode.pathTree),
        {'VidOnly'},
      );
    });
  });
}

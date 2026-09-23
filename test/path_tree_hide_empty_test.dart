import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/model/db/adapters/media_library.dart';
import 'package:iris/features/media_library/model/db/dao/media_nodes_dao.dart';
import 'package:iris/features/media_library/model/db/repositories/sub/media_node_repository.dart';
import 'package:iris/features/media_library/model/media_lib/media_library.dart';
import 'package:iris/features/media_library/model/media_lib/media_library_source.dart';
import 'package:iris/features/media_library/model/media_lib/media_node.dart';
import 'package:iris/features/media_library/services/system_library_open_check.dart';
import 'package:iris/features/media_library/view/content/model/lib_content_item.dart';
import 'package:iris/features/media_library/view/content/model/media_lib_content_mode.dart';
import 'package:iris/features/media_library/view/content/store/use_media_lib_content_store.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_storage_store.dart';

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
    useStorageStore();
    await useStorageStore().initialized;
    useMediaLibContentStore();
    await useMediaLibContentStore().initialized;
    // Disable the realtime filesystem → DB sync: the registered test
    // storages point at nonexistent paths, and a successful empty listing
    // would wipe the seeded node rows.
    final appStore = useAppStore();
    appStore.set(
        appStore.state.copyWith(useLegacyStoragePersistence: true));
  });

  MediaNode dir(String storageId, String path) {
    final segments = path.split('/');
    return MediaNode.directory(
      id: '$storageId:$path',
      storageId: storageId,
      path: segments,
      parentPath: segments.length == 1
          ? null
          : segments.sublist(0, segments.length - 1).join('/'),
      pathDepth: segments.length,
      name: segments.last,
    );
  }

  MediaNode file(String storageId, String path, MediaType mediaType) {
    final segments = path.split('/');
    return MediaNode.file(
      id: '$storageId:$path',
      storageId: storageId,
      path: segments,
      parentPath: segments.length == 1
          ? null
          : segments.sublist(0, segments.length - 1).join('/'),
      pathDepth: segments.length,
      name: segments.last,
      mediaType: mediaType,
    );
  }

  group('getDirectoryChildren hideEmptyDirs (pathTree)', () {
    late AppDatabase db;
    late MediaNodeRepository repo;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      repo = MediaNodeRepository(MediaNodesDao(db));

      // HasMedia holds a video; EmptyDir holds only an unknown file;
      // BareDir holds nothing at all.
      final dao = MediaNodesDao(db);
      await dao.insertNode(dir('st-he', 'HasMedia'));
      await dao.insertNode(file('st-he', 'HasMedia/v.mp4', MediaType.video));
      await dao.insertNode(dir('st-he', 'EmptyDir'));
      await dao.insertNode(file('st-he', 'EmptyDir/note.txt', MediaType.unknown));
      await dao.insertNode(dir('st-he', 'BareDir'));
      await dao.insertNode(file('st-he', 'root-a.mp3', MediaType.audio));
    });

    tearDown(() => db.close());

    test('hideEmptyDirs=true hides dirs without playable descendants',
        () async {
      final result = await repo.getDirectoryChildren(
        storageId: 'st-he',
        parentPath: null,
        page: 1,
        hideEmptyDirs: true,
      );
      final names = result.items.map((n) => n.name).toSet();
      expect(names, contains('HasMedia'));
      expect(names, isNot(contains('EmptyDir')),
          reason: 'only an unknown descendant');
      expect(names, isNot(contains('BareDir')), reason: 'no descendants');
    });

    test('hideEmptyDirs=true keeps file rows untouched', () async {
      final result = await repo.getDirectoryChildren(
        storageId: 'st-he',
        parentPath: null,
        page: 1,
        hideEmptyDirs: true,
      );
      expect(result.items.map((n) => n.name), contains('root-a.mp3'));
    });

    test('hideEmptyDirs=false keeps every directory (legacy)', () async {
      final result = await repo.getDirectoryChildren(
        storageId: 'st-he',
        parentPath: null,
        page: 1,
        hideEmptyDirs: false,
      );
      expect(result.items.map((n) => n.name).toSet(),
          containsAll(['HasMedia', 'EmptyDir', 'BareDir']));
    });

    test('hideEmptyDirs defaults to false', () async {
      final result = await repo.getDirectoryChildren(
        storageId: 'st-he',
        parentPath: null,
        page: 1,
      );
      expect(result.items.map((n) => n.name).toSet(),
          containsAll(['HasMedia', 'EmptyDir', 'BareDir']));
    });
  });

  group('setLibrary auto-skips the sources page for system libs', () {
    Future<({String storageId, String libraryId})> seedSystemLib(
      String suffix, {
      bool withMedia = true,
    }) async {
      final storageId = 'st-auto-$suffix';
      final libraryId =
          SystemLibraryOpenCheckService.systemLibIdFor(storageId);
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
      final store = useStorageStore();
      if (store.findById(storageId) == null) {
        store.set(store.state.copyWith(storages: [
          ...store.state.storages,
          Storage.local(
            id: storageId,
            type: StorageType.internal,
            name: storageId,
            basePath: const ['sdcard'],
          ),
        ]));
      }
      final dao = DbModule.mediaNodesDao;
      if (withMedia) {
        await dao.insertNode(MediaNode.directory(
          id: '$storageId:sdcard/Movies',
          storageId: storageId,
          path: const ['sdcard', 'Movies'],
          parentPath: 'sdcard',
          pathDepth: 2,
          name: 'Movies',
        ));
        await dao.insertNode(MediaNode.file(
          id: '$storageId:sdcard/Movies/m.mp4',
          storageId: storageId,
          path: const ['sdcard', 'Movies', 'm.mp4'],
          parentPath: 'sdcard/Movies',
          pathDepth: 3,
          name: 'm.mp4',
          mediaType: MediaType.video,
        ));
      }
      return (storageId: storageId, libraryId: libraryId);
    }

    test('pathTreeHideEmpty defaults to true', () {
      expect(useMediaLibContentStore().state.pathTreeHideEmpty, isTrue);
    });

    test('single-source system lib lands directly in source content',
        () async {
      final seeded = await seedSystemLib('t1');
      final s = useMediaLibContentStore();
      s.set(s.state.copyWith(
        currentLibraryId: null,
        currentStorageId: null,
        currentParentPath: null,
        currentSourceRootPath: null,
        viewMode: MediaLibContentMode.pathTree,
      ));
      await s.setLibrary(seeded.libraryId);

      expect(s.state.currentStorageId, seeded.storageId);
      expect(s.state.currentParentPath, isNotNull);
      expect(
        s.runtime.items.whereType<SourceLibContentItem>(),
        isEmpty,
        reason: 'sources page must be skipped',
      );
      expect(s.runtime.items.map((i) => i.title), contains('Movies'));
    });

    test('navigateUp from the auto-entered root returns to the lib list',
        () async {
      final seeded = await seedSystemLib('t2');
      final s = useMediaLibContentStore();
      s.set(s.state.copyWith(
        currentLibraryId: null,
        currentStorageId: null,
        currentParentPath: null,
        currentSourceRootPath: null,
        viewMode: MediaLibContentMode.pathTree,
      ));
      await s.setLibrary(seeded.libraryId);

      final wentUp = await s.navigateUp();
      expect(wentUp, isFalse,
          reason: 'back from the auto-entered root must close to libs');
    });

    test('user lib with a single source still shows the sources page',
        () async {
      const libraryId = 'user-single-source-lib';
      const storageId = 'st-auto-user1';
      final now = DateTime.now();
      await DbModule.mediaLibsDao.upsert(MediaLibrary(
        id: libraryId,
        name: libraryId,
        type: MediaLibraryType.user,
        createdAt: now,
        updatedAt: now,
      ).toCompanion());
      await DbModule.mediaLibSourcesDao.upsertSource(MediaLibrarySource(
        id: 0,
        libraryId: libraryId,
        storageId: storageId,
        path: null,
      ));

      final s = useMediaLibContentStore();
      s.set(s.state.copyWith(
        currentLibraryId: null,
        currentStorageId: null,
        currentParentPath: null,
        currentSourceRootPath: null,
        viewMode: MediaLibContentMode.pathTree,
      ));
      await s.setLibrary(libraryId);

      expect(s.state.currentStorageId, isNull);
      expect(s.runtime.items.whereType<SourceLibContentItem>(), isNotEmpty);
    });

    test('detached lib with several sources still shows the sources page',
        () async {
      const libraryId = SystemLibraryOpenCheckService.detachedLibId;
      final now = DateTime.now();
      await DbModule.mediaLibsDao.upsert(MediaLibrary(
        id: libraryId,
        name: 'Detached',
        type: MediaLibraryType.system,
        createdAt: now,
        updatedAt: now,
      ).toCompanion());
      for (final sid in ['st-detached-a', 'st-detached-b']) {
        await DbModule.mediaLibSourcesDao.upsertSource(MediaLibrarySource(
          id: 0,
          libraryId: libraryId,
          storageId: sid,
          path: null,
        ));
      }

      final s = useMediaLibContentStore();
      s.set(s.state.copyWith(
        currentLibraryId: null,
        currentStorageId: null,
        currentParentPath: null,
        currentSourceRootPath: null,
        viewMode: MediaLibContentMode.pathTree,
      ));
      await s.setLibrary(libraryId);

      expect(s.state.currentStorageId, isNull);
      expect(s.runtime.items.whereType<SourceLibContentItem>(), isNotEmpty);
    });

    test('updatePathTreeHideEmpty(false) reveals empty dirs again', () async {
      final seeded = await seedSystemLib('t3');
      final dao = DbModule.mediaNodesDao;
      await dao.insertNode(MediaNode.directory(
        id: '${seeded.storageId}:sdcard/Empty',
        storageId: seeded.storageId,
        path: const ['sdcard', 'Empty'],
        parentPath: 'sdcard',
        pathDepth: 2,
        name: 'Empty',
      ));

      final s = useMediaLibContentStore();
      s.set(s.state.copyWith(
        currentLibraryId: null,
        currentStorageId: null,
        currentParentPath: null,
        currentSourceRootPath: null,
        viewMode: MediaLibContentMode.pathTree,
        pathTreeHideEmpty: true,
      ));
      await s.setLibrary(seeded.libraryId);
      expect(s.runtime.items.map((i) => i.title), isNot(contains('Empty')));

      await s.updatePathTreeHideEmpty(false);
      expect(s.runtime.items.map((i) => i.title), contains('Empty'));
    });

    test('probe distinguishes filtered-empty from truly empty', () async {
      // Filtered-empty: the auto-entered root holds only an empty dir, so
      // the filtered listing is empty while unfiltered rows exist.
      final seeded = await seedSystemLib('t4', withMedia: false);
      final dao = DbModule.mediaNodesDao;
      await dao.insertNode(MediaNode.directory(
        id: '${seeded.storageId}:sdcard/Empty',
        storageId: seeded.storageId,
        path: const ['sdcard', 'Empty'],
        parentPath: 'sdcard',
        pathDepth: 2,
        name: 'Empty',
      ));

      final s = useMediaLibContentStore();
      s.set(s.state.copyWith(
        currentLibraryId: null,
        currentStorageId: null,
        currentParentPath: null,
        currentSourceRootPath: null,
        viewMode: MediaLibContentMode.pathTree,
        pathTreeHideEmpty: true,
      ));
      await s.setLibrary(seeded.libraryId);
      expect(s.runtime.items, isEmpty);
      expect(
        await s.pathTreeHasUnfilteredRows(),
        isTrue,
        reason: 'unfiltered rows exist, the filter hid them',
      );

      // Truly empty: no node rows at all under the auto-entered root.
      final bare = await seedSystemLib('t5', withMedia: false);
      s.set(s.state.copyWith(
        currentLibraryId: null,
        currentStorageId: null,
        currentParentPath: null,
        currentSourceRootPath: null,
        viewMode: MediaLibContentMode.pathTree,
        pathTreeHideEmpty: true,
      ));
      await s.setLibrary(bare.libraryId);
      expect(s.runtime.items, isEmpty);
      expect(await s.pathTreeHasUnfilteredRows(), isFalse);
    });
  });
}

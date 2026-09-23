import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/model/db/adapters/media_library.dart';
import 'package:iris/features/media_library/model/enum/media_lib_sources.dart';
import 'package:iris/features/media_library/model/media_lib/media_library.dart';
import 'package:iris/features/media_library/model/media_lib/media_library_source.dart';
import 'package:iris/features/media_library/model/media_lib/media_node.dart';
import 'package:iris/features/media_library/search/data_source/media_search_data_source.dart';
import 'package:iris/features/media_library/services/system_library_open_check.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_storage_store.dart';

/// Guards the detached-library contract: one `sys_detached` system lib
/// collects sources whose storage entry is gone, so stale node rows stay
/// reachable instead of vanishing with their per-storage system lib.
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
    // openCheck is a hard no-op in legacy mode; the detached lib only
    // exists in the DB-backed world.
    final appStore = useAppStore();
    appStore.set(appStore.state.copyWith(useLegacyStoragePersistence: false));
  });

  Future<void> seedStorage(String storageId) =>
      DbModule.storageRepo.addStorage(Storage.local(
        id: storageId,
        type: StorageType.internal,
        name: storageId,
        basePath: const ['sdcard'],
      ));

  group('detached system library', () {
    test('openCheck creates the detached lib exactly once', () async {
      await SystemLibraryOpenCheckService.openCheck();
      await SystemLibraryOpenCheckService.openCheck();

      final lib = await DbModule.mediaLibsDao
          .getById(SystemLibraryOpenCheckService.detachedLibId);
      expect(lib, isNotNull);
      expect(lib!.name, SystemLibraryOpenCheckService.detachedLibName);
      final all = await DbModule.mediaLibsDao.getAll();
      expect(
        all.where((l) => l.id == SystemLibraryOpenCheckService.detachedLibId),
        hasLength(1),
      );
    });

    test('removed storage system lib is re-homed under the detached lib',
        () async {
      const storageId = 'st-detached-gone';
      final libId = SystemLibraryOpenCheckService.systemLibIdFor(storageId);
      final now = DateTime.now();
      await DbModule.mediaLibsDao.upsert(MediaLibrary(
        id: libId,
        name: libId,
        type: MediaLibraryType.system,
        createdAt: now,
        updatedAt: now,
      ).toCompanion());
      await DbModule.mediaLibSourcesDao.upsertSource(MediaLibrarySource(
        id: 0,
        libraryId: libId,
        storageId: storageId,
        path: null,
        name: storageId,
        kind: MediaSourceKind.storage,
      ));
      await DbModule.mediaNodesDao.insertNode(MediaNode.file(
        id: '$storageId:sdcard/v.mp4',
        storageId: storageId,
        path: const ['sdcard', 'v.mp4'],
        parentPath: 'sdcard',
        pathDepth: 2,
        name: 'v.mp4',
        mediaType: MediaType.video,
      ));

      await SystemLibraryOpenCheckService.openCheck();

      // System lib dropped, nodes untouched, source re-homed.
      expect(await DbModule.mediaLibsDao.getById(libId), isNull);
      expect(
        await DbModule.mediaNodesDao.getByPath(storageId, 'sdcard/v.mp4'),
        isNotNull,
      );
      final detached = await DbModule.mediaLibSourcesDao
          .getLibrarySources(SystemLibraryOpenCheckService.detachedLibId);
      final rehomed =
          detached.where((s) => s.storageId == storageId).toList();
      expect(rehomed, hasLength(1));
      expect(rehomed.single.name, 'Detached: $storageId');
    });

    test('present storage regains its system lib and drops the detached source',
        () async {
      const storageId = 'st-detached-back';
      await seedStorage(storageId);
      final now = DateTime.now();
      await DbModule.mediaLibsDao.upsert(MediaLibrary(
        id: SystemLibraryOpenCheckService.detachedLibId,
        name: SystemLibraryOpenCheckService.detachedLibName,
        type: MediaLibraryType.system,
        createdAt: now,
        updatedAt: now,
      ).toCompanion());
      await DbModule.mediaLibSourcesDao.upsertSource(MediaLibrarySource(
        id: 0,
        libraryId: SystemLibraryOpenCheckService.detachedLibId,
        storageId: storageId,
        path: null,
        name: 'Detached: $storageId',
        kind: MediaSourceKind.storage,
      ));

      await SystemLibraryOpenCheckService.openCheck();

      final libId = SystemLibraryOpenCheckService.systemLibIdFor(storageId);
      expect(await DbModule.mediaLibsDao.getById(libId), isNotNull);
      final leftovers =
          await DbModule.mediaLibSourcesDao.getByStorageId(storageId);
      expect(
        leftovers.where(
            (r) => r.libraryId == SystemLibraryOpenCheckService.detachedLibId),
        isEmpty,
      );
    });

    test('resolveLibraryForStorage skips the detached lib', () async {
      const storageId = 'st-detached-only';
      expect(
        await DbModule.mediaLibSourcesDao.getByStorageId(storageId),
        isEmpty,
      );
      await DbModule.mediaLibSourcesDao.upsertSource(MediaLibrarySource(
        id: 0,
        libraryId: SystemLibraryOpenCheckService.detachedLibId,
        storageId: storageId,
        path: null,
        name: 'Detached: $storageId',
        kind: MediaSourceKind.storage,
      ));

      expect(await resolveLibraryForStorage(storageId), isNull);
    });
  });
}

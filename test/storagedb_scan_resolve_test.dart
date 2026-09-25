import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/model/enum/basic_enum.dart'
    show SortDirection;
import 'package:iris/features/media_library/model/enum/media_lib_sources.dart'
    show MediaSourceKind;
import 'package:iris/features/media_library/model/enum/media_node.dart';
import 'package:iris/features/media_library/scan/service/recursive_scan_service.dart';
import 'package:iris/features/media_library/scan/store/recursive_scan_store.dart';
import 'package:iris/features/scenario_playback/model/enum/scenario_sort_field.dart';
import 'package:iris/features/scenario_playback/store/use_playback_scenario_store.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/models/db/storage_path_codec.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_play_queue_store.dart';
import 'package:iris/store/use_storage_store.dart';

/// Regression for the storagedb scan→play flow: a recursive scan of the storage
/// ROOT used to write the storage base itself as the children's `parent_path`,
/// which relativizes to `''` — a form no `parent_path IS NULL` root read could
/// match. The files were displayed but the folder-scope play pre-check (file
/// tap) reported "no playable content", and the root recursive resolve emitted
/// only an unavailable placeholder (the bottom play button silently did
/// nothing). Covers both the fixed producer and legacy `''` rows.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureStorageChannel, (call) async => null);

  late AppDatabase db;

  setUpAll(() async {
    db = AppDatabase(NativeDatabase.memory());
    DbModule.init(db);
    usePlaybackScenarioStore();
    await usePlaybackScenarioStore().initialized;
    usePlayQueueStore();
    await usePlayQueueStore().initialized;
    useAppStore();
    await useAppStore().initialized;
    useStorageStore();
    await useStorageStore().initialized;
  });

  tearDownAll(() {
    StoragePathCodec.baseResolver = (_) => null;
    db.close();
  });

  setUp(() async {
    final store = usePlaybackScenarioStore();
    final sys = await store.ensureSystemPlayingScenario();
    await store.setActiveScenario(sys.id);
    await store.clearSources(sys.id);
    await store.clearExplicitItems(sys.id);
  });

  /// Scans a temp dir holding a single `v.mp4`, wires the storage base, and
  /// returns the storage. Registers the storage so [StoragePathCodec] relativizes.
  Future<Storage> scanRoot(WidgetTester tester, String storageId) async {
    final tempDir = await Directory.systemTemp.createTemp('scan_resolve');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    File('${tempDir.path}/v.mp4').writeAsStringSync('');
    Directory('${tempDir.path}/sub').createSync();
    File('${tempDir.path}/sub/n.mp4').writeAsStringSync('');

    final storage = Storage.local(
      id: storageId,
      type: StorageType.internal,
      name: 't',
      basePath: [tempDir.path],
    );
    StoragePathCodec.baseResolver =
        (id) => id == storage.id ? storage.basePath : null;
    await useStorageStore().addStorage(storage);

    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      }),
    ));

    final scanStore = RecursiveScanStore();
    await scanStore.initialized;
    await RecursiveScanService(
      storage: storage,
      scanStore: scanStore,
      nodesDao: DbModule.mediaNodesDao,
      sourcesDao: DbModule.mediaLibSourcesDao,
      probeService: null,
    ).scanRecursively(rootPaths: [tempDir.path], context: ctx);

    return storage;
  }

  Future<void> installRootSource(Storage storage) async {
    final store = usePlaybackScenarioStore();
    await store.ensureSystemPlayingScenario();
    await store.addSource(
      storageId: storage.id,
      path: storage.basePath.join('/'),
      recursive: true,
    );
    await store.applyQueueGenerationRule(
      sortField: ScenarioSortField.name,
      sortDirection: SortDirection.asc,
    );
    await store.bumpPlaybackVersion();
  }

  testWidgets('scanned root children use a NULL parent and resolve to the file',
      (tester) async {
    await tester.runAsync(() async {
      final storage = await scanRoot(tester, 'st-scan-null');

      // Producer fix: storage-root children must be stored with a NULL parent.
      final rows =
          await DbModule.mediaNodesDao.getDirectChildren(storage.id, '');
      expect(rows.map((r) => r.path), containsAll(<String>['v.mp4', 'sub']));
      final rootFile = rows.firstWhere((r) => r.path == 'v.mp4');
      expect(rootFile.parentPath, isNull,
          reason: 'a root-level child must not store an empty parent_path');
      final subDir = rows.firstWhere((r) => r.path == 'sub');
      expect(subDir.parentPath, isNull);

      // File-tap pre-check (non-recursive root folder scope): only the DIRECT
      // child file, not the one nested in `sub`.
      final pre = await DbModule.mediaNodeRepo.getPagedNodesForSources(
        sources: [
          (
            storageId: storage.id,
            path: storage.basePath.join('/'),
            kind: MediaSourceKind.directory,
            recursive: false,
            scenarioSourceId: null,
          ),
        ],
        nodeKind: MediaNodeKind.file,
        page: 0,
        pageSize: 10,
      );
      expect(pre.totalItems, 1,
          reason: 'the file tap must find the root-level file');
      expect(pre.items.single.name, 'v.mp4');

      // Bottom play button: recursive whole-storage scope must resolve BOTH the
      // root-level file and the nested one.
      await installRootSource(storage);
      final resolved =
          await usePlaybackScenarioStore().resolvePage(page: 0, pageSize: 100);
      expect(resolved.totalItems, 2);
      expect(resolved.items.every((e) => e.available), isTrue);
      expect(resolved.items.map((e) => e.media.name).toSet(),
          <String>{'v.mp4', 'n.mp4'});
    });
  });

  testWidgets('legacy empty parent_path rows stay resolvable (tolerant reads)',
      (tester) async {
    await tester.runAsync(() async {
      final storage = await scanRoot(tester, 'st-scan-legacy');

      // Simulate a row written before the producer fix.
      await DbModule.mediaNodesDao.customStatement(
          "UPDATE media_nodes SET parent_path = '' WHERE path = 'v.mp4'");

      final pre = await DbModule.mediaNodeRepo.getPagedNodesForSources(
        sources: [
          (
            storageId: storage.id,
            path: storage.basePath.join('/'),
            kind: MediaSourceKind.directory,
            recursive: false,
            scenarioSourceId: null,
          ),
        ],
        nodeKind: MediaNodeKind.file,
        page: 0,
        pageSize: 1,
      );
      expect(pre.totalItems, 1,
          reason: 'legacy empty-parent rows must still match root queries');
      expect(pre.items.single.name, 'v.mp4');

      await installRootSource(storage);
      final resolved =
          await usePlaybackScenarioStore().resolvePage(page: 0, pageSize: 100);
      expect(resolved.totalItems, 2);
      expect(resolved.items.every((e) => e.available), isTrue);
      expect(resolved.items.map((e) => e.media.name).toSet(),
          <String>{'v.mp4', 'n.mp4'});
    });
  });
}

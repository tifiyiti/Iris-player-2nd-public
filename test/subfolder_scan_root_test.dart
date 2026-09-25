import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/scan/service/recursive_scan_service.dart';
import 'package:iris/features/media_library/scan/store/recursive_scan_store.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/models/db/storage_path_codec.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/storages/file_list_result.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/utils/path_conv.dart';
import 'package:path/path.dart' as p;

/// Regression for "scanned but gate says unscanned" on subfolder-base
/// storages (e.g. a manually added `F:/dl/ar` tile scanned from its trailing
/// button, then Play current folder reports "never fully scanned").
///
/// A tile scan passes the ABSOLUTE base as the scan root. The service used to
/// build directory nodes from those absolute segments, so above-base
/// phantoms (`F:`, `F:/dl`, the latter as the root's parent) were stored.
/// The phantom with a NULL parent then counted as an unscanned root child
/// forever, permanently blocking the root `scanDone` stamp — while the real
/// subdirectories below it were all marked done.
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
  });

  tearDownAll(() {
    StoragePathCodec.baseResolver = (_) => null;
    db.close();
  });

  /// Seeds `tmp/dl/ar/{v.mp4,kid/n.mp4}` and returns a storage whose base is
  /// the SUBFOLDER `ar` (multi-segment base, like a picked Windows folder).
  Future<Storage> seedSubfolderBase(String storageId) async {
    final tempDir = await Directory.systemTemp.createTemp('sub_scan');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final sub = Directory(p.join(tempDir.path, 'dl', 'ar'))
      ..createSync(recursive: true);
    File(p.join(sub.path, 'v.mp4')).writeAsStringSync('');
    Directory(p.join(sub.path, 'kid')).createSync();
    File(p.join(sub.path, 'kid', 'n.mp4')).writeAsStringSync('');

    final storage = Storage.local(
      id: storageId,
      type: StorageType.internal,
      name: 'ar',
      basePath: pathConv(sub.path),
    );
    expect(storage.basePath.length, greaterThan(1),
        reason: 'the fixture must use a multi-segment subfolder base');
    StoragePathCodec.baseResolver =
        (id) => id == storage.id ? storage.basePath : null;
    return storage;
  }

  Future<BuildContext> pumpCtx(WidgetTester tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      }),
    ));
    return ctx;
  }

  /// Tile-style scan: the storage tile passes the absolute base, exactly like
  /// `StoragesDbList.startStorageScan` (`basePath.join('/')`).
  Future<void> tileScan(WidgetTester tester, Storage storage) async {
    final ctx = await pumpCtx(tester);
    final scanStore = RecursiveScanStore();
    await scanStore.initialized;
    await RecursiveScanService(
      storage: storage,
      scanStore: scanStore,
      nodesDao: DbModule.mediaNodesDao,
      sourcesDao: DbModule.mediaLibSourcesDao,
      probeService: null,
    ).scanRecursively(
      rootPaths: [storage.basePath.join('/')],
      context: ctx,
    );
  }

  Future<List<String>> allStoredPaths(String storageId) async {
    final out = <String>[];
    final roots = await DbModule.mediaNodesDao.getRootLevelNodes(storageId);
    final queue = roots.map((r) => r.path).toList();
    final seen = <String>{};
    while (queue.isNotEmpty) {
      final path = queue.removeAt(0);
      if (!seen.add(path)) continue;
      out.add(path);
      final kids =
          await DbModule.mediaNodesDao.getDirectChildren(storageId, path);
      queue.addAll(kids.map((k) => k.path));
    }
    // The '' root self-node has no parent and is not its own child.
    final self = await DbModule.mediaNodesDao.getByPath(storageId, '');
    if (self != null && !seen.contains('')) out.add('');
    return out;
  }

  testWidgets('absolute base scan marks the root scanDone, no phantoms',
      (tester) async {
    await tester.runAsync(() async {
      final storage = await seedSubfolderBase('st-sub-root');

      await tileScan(tester, storage);

      // The exact row the play gate reads must be done ...
      final status = await DbModule.mediaNodesDao
          .dirScanStatus(storage.id, storage.basePath.join('/'));
      expect(status?.state, 'scanDone');

      // ... the '' self-node parents at the storage root ...
      final self = await DbModule.mediaNodesDao.getByPath(storage.id, '');
      expect(self, isNotNull);
      expect(self!.parentPath, isNull);

      // ... and no above-base phantom may exist.
      for (final path in await allStoredPaths(storage.id)) {
        expect(
          StoragePathCodec.isAboveBase(storage.id, canonicalDbPath(path)),
          isFalse,
          reason: 'phantom above-base row: $path',
        );
      }
    });
  });

  testWidgets('pre-existing phantoms are healed by the next scan',
      (tester) async {
    await tester.runAsync(() async {
      final storage = await seedSubfolderBase('st-sub-heal');
      final dao = DbModule.mediaNodesDao;
      final above =
          storage.basePath.sublist(0, storage.basePath.length - 1).join('/');
      final aboveAbove =
          storage.basePath.sublist(0, storage.basePath.length - 2).join('/');

      // Simulate rows written by the pre-fix scanner.
      await dao.customStatement(
        "INSERT INTO media_nodes (storage_id, data_scope_id, path, parent_path, node_kind, name) "
        "VALUES ('${storage.id}', '${storage.id}', '$aboveAbove', NULL, 'directory', 'x')",
      );
      await dao.customStatement(
        "INSERT INTO media_nodes (storage_id, data_scope_id, path, parent_path, node_kind, name) "
        "VALUES ('${storage.id}', '${storage.id}', '$above', '$aboveAbove', 'directory', 'y')",
      );

      await tileScan(tester, storage);

      expect(await dao.getByPath(storage.id, aboveAbove), isNull);
      expect(await dao.getByPath(storage.id, above), isNull);
      expect(
        (await dao.dirScanStatus(storage.id, storage.basePath.join('/')))
            ?.state,
        'scanDone',
      );
    });
  });

  testWidgets('drive-root base: absolute self phantom is healed',
      (tester) async {
    await tester.runAsync(() async {
      const storageId = 'st-drive-root';
      final storage = Storage.local(
        id: storageId,
        type: StorageType.internal,
        name: 'F',
        basePath: const ['F:'],
      );
      StoragePathCodec.baseResolver =
          (id) => id == storageId ? storage.basePath : null;
      final dao = DbModule.mediaNodesDao;

      // Simulate the pre-fix root self node: the base stored in ABSOLUTE form
      // (`F:`) with a NULL parent. `isAboveBase` does not match it (it is the
      // base itself, not strictly above it), yet with a NULL parent it counts
      // as an unscanned root child forever, permanently blocking the root
      // `scanDone` stamp on drive-root storages.
      await dao.customStatement(
        "INSERT INTO media_nodes (storage_id, data_scope_id, path, parent_path, node_kind, name) "
        "VALUES ('$storageId', '$storageId', 'F:', NULL, 'directory', 'F:')",
      );

      final ctx = await pumpCtx(tester);
      final scanStore = RecursiveScanStore();
      await scanStore.initialized;
      await RecursiveScanService(
        storage: storage,
        scanStore: scanStore,
        nodesDao: DbModule.mediaNodesDao,
        sourcesDao: DbModule.mediaLibSourcesDao,
        probeService: null,
        listDir: (s, p) async => p.join('/') == 'F:'
            ? FileListResult([
                FileItem(name: 'kid', uri: 'F:/kid', isDir: true),
              ])
            : const FileListResult(<FileItem>[]),
      ).scanRecursively(
        rootPaths: [storage.basePath.join('/')],
        context: ctx,
      );

      // The absolute-form phantom must be gone (exact stored path, not via a
      // prefix delete that would also wipe the real root container) ...
      expect(await dao.getByPathRaw(storageId, 'F:'), isNull);
      // ... and the exact row the play gate reads must be done.
      expect(
        (await dao.dirScanStatus(storageId, storage.basePath.join('/')))
            ?.state,
        'scanDone',
      );
      final self = await dao.getByPath(storageId, '');
      expect(self, isNotNull);
      expect(self!.parentPath, isNull);
    });
  });
}

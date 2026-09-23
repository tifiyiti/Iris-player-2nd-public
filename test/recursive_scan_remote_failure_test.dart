import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/model/db/adapters/media_node_drift_adapter.dart';
import 'package:iris/features/media_library/model/media_lib/media_node.dart';
import 'package:iris/features/media_library/scan/service/recursive_scan_service.dart';
import 'package:iris/features/media_library/scan/store/recursive_scan_store.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/models/enums/storage_list_error.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/storages/file_list_result.dart';
import 'package:iris/models/storages/storage.dart';

// Remote safety contract for the recursive scanner: a failed listing
// (unreachable / unauthorized / timeout) must never be treated as an empty
// directory, because the incremental sync would then delete the snapshot rows.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureStorageChannel, (call) async => null);

  setUpAll(() async {
    await DbModule.init(AppDatabase(NativeDatabase.memory()));
  });

  Storage storage() => Storage.ftp(
        id: 'st1',
        name: 'FTP',
        host: '10.0.0.2',
        basePath: const [''],
        port: '21',
        username: 'u',
        password: 'p',
      );

  Future<void> seed() async {
    await DbModule.mediaNodesDao.batchUpsert([
      MediaNode.directory(
        id: 'st1:a',
        storageId: 'st1',
        path: const ['a'],
        pathDepth: 1,
        name: 'a',
      ).toCompanion(),
      MediaNode.directory(
        id: 'st1:a/b',
        storageId: 'st1',
        path: const ['a', 'b'],
        parentPath: 'a',
        pathDepth: 2,
        name: 'b',
      ).toCompanion(),
      MediaNode.file(
        id: 'st1:a/b/v.mp4',
        storageId: 'st1',
        path: const ['a', 'b', 'v.mp4'],
        parentPath: 'a/b',
        pathDepth: 3,
        name: 'v.mp4',
        mediaType: MediaType.video,
        sizeInBytes: 10,
      ).toCompanion(),
    ]);
  }

  Future<BuildContext> contextOf(WidgetTester tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(builder: (c) {
          ctx = c;
          return const SizedBox();
        }),
      ),
    );
    return ctx;
  }

  testWidgets('failed remote listing preserves rows and stamps error',
      (tester) async {
    final ctx = await contextOf(tester);
    // runAsync: the scanner's cooperative yields use real timers, which the
    // widget-test fake-async zone would otherwise never advance.
    await tester.runAsync(() async {
      await seed();
      final scanStore = RecursiveScanStore();
      await scanStore.initialized;
      final service = RecursiveScanService(
        storage: storage(),
        scanStore: scanStore,
        nodesDao: DbModule.mediaNodesDao,
        sourcesDao: DbModule.mediaLibSourcesDao,
        listDir: (s, p) async => const FileListResult(
          <FileItem>[],
          errorKind: StorageListErrorKind.unreachable,
          errorDetail: 'connection refused',
        ),
      );

      await service.scanRecursively(rootPaths: const ['a'], context: ctx);

      // Snapshot rows survive: a failure is not "empty".
      final children =
          await DbModule.mediaNodesDao.getDirectChildren('st1', 'a');
      expect(children.map((c) => c.path), contains('a/b'));

      // The dir keeps its error stamp (the aggregate pass must not stamp it
      // done).
      expect(
        (await DbModule.mediaNodesDao.dirScanStatus('st1', 'a'))?.state,
        'error',
      );
    });
  });

  testWidgets('successful empty listing prunes stale rows', (tester) async {
    final ctx = await contextOf(tester);
    await tester.runAsync(() async {
      await seed();
      final scanStore = RecursiveScanStore();
      await scanStore.initialized;
      final service = RecursiveScanService(
        storage: storage(),
        scanStore: scanStore,
        nodesDao: DbModule.mediaNodesDao,
        sourcesDao: DbModule.mediaLibSourcesDao,
        listDir: (s, p) async => FileListResult.empty,
      );

      await service.scanRecursively(rootPaths: const ['a'], context: ctx);

      final children =
          await DbModule.mediaNodesDao.getDirectChildren('st1', 'a');
      expect(children, isEmpty);
      expect(
        (await DbModule.mediaNodesDao.dirScanStatus('st1', 'a'))?.state,
        'scanDone',
      );
    });
  });
}

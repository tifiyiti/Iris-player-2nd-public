import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/view/files_db_paging/storage_browser_data_source.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_play_queue_store.dart';
import 'package:iris/store/use_storage_store.dart';

/// The filtered/sorted page must be memoized: `items`, `totalItems` and
/// `totalPages` are read many times per build, and recomputing them with a
/// search active is O(N) each time.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureStorageChannel, (call) async => null);

  setUpAll(() async {
    await DbModule.init(AppDatabase(NativeDatabase.memory()));
    await runZonedGuarded(() async {
      usePlayQueueStore();
      await usePlayQueueStore().initialized;
      useAppStore();
      await useAppStore().initialized;
      useStorageStore();
      await useStorageStore().initialized;
    }, (Object e, StackTrace st) {});
  });

  group('StorageBrowserDataSource filter cache', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('sb_filter');
      File('${tempDir.path}/a.mp4').writeAsStringSync('');
      File('${tempDir.path}/b.mp4').writeAsStringSync('');
      File('${tempDir.path}/c.mp3').writeAsStringSync('');
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    Future<StorageBrowserDataSource> load() async {
      final ds = StorageBrowserDataSource(Storage.local(
        type: StorageType.internal,
        name: 't',
        basePath: [tempDir.path],
      ));
      addTearDown(ds.dispose);
      await ds.loadFromStorage();
      return ds;
    }

    test('repeated reads do not recompute the filtered list', () async {
      final ds = await load();
      ds.items; // warm the cache
      final before = ds.debugFilterComputeCount;

      // Simulate one page build: the bar plus the list read these repeatedly.
      for (var i = 0; i < 50; i++) {
        ds.items;
        ds.totalItems;
        ds.totalPages;
      }
      ds.items;
      expect(ds.debugFilterComputeCount, before,
          reason: 'no getter read may recompute the filtered list');
    });

    test('changing the search query recomputes and reflects the new results',
        () async {
      final ds = await load();
      final all = ds.totalItems;
      expect(all, 3);

      ds.setSearchQueryForTest('a');
      expect(ds.totalItems, 1, reason: 'search must narrow the result set');
      expect(ds.items.single.name, 'a.mp4');

      ds.setSearchQueryForTest(null);
      expect(ds.totalItems, all, reason: 'clearing search restores the set');
    });
  });
}

import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/view/files_db_paging/storage_browser_data_source.dart';
import 'package:iris/features/meta_settings/engine/browse_media_scope.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_play_queue_store.dart';
import 'package:iris/store/use_storage_store.dart';

/// Browse-media-scope wiring for the filesystem-first storage browser:
/// `_applySort` must apply FileItem.matchesBrowseScope on top of isVisible.
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

  tearDown(() async {
    final store = useAppStore();
    store.set(store.state.copyWith(
      browseMediaScope: BrowseMediaScope.all,
      useMetadataSettings: false,
    ));
  });

  group('StorageBrowserDataSource honors browse scope', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('browse_scope');
      Directory('${tempDir.path}/sub').createSync();
      File('${tempDir.path}/v.mp4').writeAsStringSync('');
      File('${tempDir.path}/a.mp3').writeAsStringSync('');
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    Future<Set<String>> browseNames() async {
      final ds = StorageBrowserDataSource(Storage.local(
        type: StorageType.internal,
        name: 't',
        basePath: [tempDir.path],
      ));
      addTearDown(ds.dispose);
      await ds.loadFromStorage();
      return ds.items.map((f) => f.name).toSet();
    }

    test('videoOnly hides audio files but keeps dirs', () async {
      await useAppStore().setMetadataGate(true);
      await useAppStore().updateBrowseMediaScope(BrowseMediaScope.videoOnly);

      expect(await browseNames(), {'sub', 'v.mp4'});
    });

    test('gate OFF keeps everything visible (legacy)', () async {
      await useAppStore().setMetadataGate(false);

      expect(await browseNames(), {'sub', 'v.mp4', 'a.mp3'});
    });
  });
}

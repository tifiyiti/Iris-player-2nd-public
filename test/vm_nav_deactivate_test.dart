import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/virtual_media/model/domain/vm_item.dart';
import 'package:iris/features/virtual_media/playback/vm_playback_controller.dart';
import 'package:iris/features/virtual_media/store/vm_playback_store.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/models/file.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_play_queue_store.dart';

import 'helpers/sqlite3_loader.dart';

VirtualMediaItem _item() => VirtualMediaItem(
      ruleId: 'r',
      scopeKey: 'r|d|#1',
      rootPath: 'd',
      displayIndex: 1,
      displayName: 'd',
      segments: const [
        VirtualSegment(
          mediaKey: 'st1:d/a.mp4',
          storageId: 'st1',
          path: ['d', 'a.mp4'],
          name: 'a.mp4',
          parentPath: 'd',
          durationMs: 60000,
        ),
      ],
    );

/// Cross-item navigation must NOT tear down the play queue or autoplay:
/// the next feed overwrites both, so deactivation clears session state +
/// timers only (no empty-queue flash through listeners).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqlite3Loaded();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureStorageChannel, (call) async => null);

  setUpAll(() async {
    await DbModule.init(AppDatabase(NativeDatabase.memory()));
    useAppStore();
    await useAppStore().initialized;
    usePlayQueueStore();
    await usePlayQueueStore().initialized;
  });

  test('deactivateForNavigation clears session, keeps queue + autoplay',
      () async {
    final file = FileItem(name: 'a.mp4', uri: 'file:///a.mp4', path: ['a.mp4']);
    await usePlayQueueStore().update(
      playQueue: [PlayQueueItem(file: file, index: 0)],
      index: 0,
    );
    await useAppStore().updateAutoPlay(true);
    useVmPlaybackStore().replace(VmPlaybackState(item: _item()));

    await VirtualMediaController.instance.deactivateForNavigation();

    expect(useVmPlaybackStore().state.item, isNull);
    expect(usePlayQueueStore().state.playQueue, hasLength(1));
    expect(useAppStore().state.autoPlay, isTrue);
  });

  test('deactivateForNavigation with no session is a no-op', () async {
    useVmPlaybackStore().replace(const VmPlaybackState());
    await VirtualMediaController.instance.deactivateForNavigation();
    expect(useVmPlaybackStore().state.item, isNull);
  });
}

import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/model/media_lib/media_node.dart';
import 'package:iris/features/virtual_media/model/domain/vm_item.dart';
import 'package:iris/features/virtual_media/playback/vm_playback_controller.dart';
import 'package:iris/features/virtual_media/store/vm_playback_store.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_play_queue_store.dart';

import 'helpers/sqlite3_loader.dart';

/// Orphaned-transition release (dial ring rendering a normal file as virtual).
///
/// A direct normal-file open lands while a VM switch is still in flight:
/// `isActive` goes false for good, yet `clearTransition()` — the only release
/// of `transitioning` — is gated on `isActive`, while `reconcileStaleSession`
/// refuses to run while `transitioning` is set. The two guard on each other
/// (deadlock), so the store's item is pinned and every progress surface keeps
/// partitioning a normal file into virtual segments.
VirtualMediaItem _item() => VirtualMediaItem(
      ruleId: 'r',
      scopeKey: 'r|d|#1',
      rootPath: 'd',
      displayIndex: 1,
      displayName: 'd',
      segments: [
        VirtualSegment(
          mediaKey: 's:d/a.mp4',
          storageId: 's',
          path: const ['d', 'a.mp4'],
          name: 'a.mp4',
          parentPath: 'd',
          durationMs: 100000,
        ),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqlite3Loaded();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureStorageChannel, (call) async => null);

  final ctrl = VirtualMediaController.instance;

  setUpAll(() async {
    await DbModule.init(AppDatabase(NativeDatabase.memory()));
    useAppStore();
    await useAppStore().initialized;
    usePlayQueueStore();
    await usePlayQueueStore().initialized;
  });

  setUp(() async {
    useVmPlaybackStore().replace(const VmPlaybackState());
    await usePlayQueueStore().clear();
  });

  tearDown(() => ctrl.debugNodeLoaderOverride = null);

  test('an orphaned transition deadlocks the cleanup until it is released',
      () {
    useVmPlaybackStore().replace(VmPlaybackState(
      item: _item(),
      transitioning: true,
      pendingSeekMs: 0,
    ));
    // The play queue carries a normal file, so the session can never regain
    // `isActive` — the precondition that made the release unreachable.
    expect(ctrl.isActive, isFalse);

    // The deadlock, reproduced: `transitioning` blocks the cleanup, while the
    // only thing that could clear `transitioning` (clearTransition) requires
    // `isActive`. The hooks' deps-keyed reconcile bails once and never
    // retries, so the item would stay pinned forever.
    ctrl.reconcileStaleSession();
    expect(useVmPlaybackStore().state.item, isNotNull,
        reason: 'reproduce the reported bug: the stale item never drops');

    // Duration arrival of the file that replaced the session takes the orphan
    // branch in both player hooks.
    ctrl.releaseOrphanedTransition();

    expect(useVmPlaybackStore().state.transitioning, isFalse,
        reason: 'the orphaned freeze must be released before cleanup');
    expect(useVmPlaybackStore().state.item, isNull,
        reason: 'the decorations must drop off the normal file');
  });

  test('a genuine in-flight feed is left alone by the orphan release',
      () async {
    final gate = Completer<MediaNode?>();
    ctrl.debugNodeLoaderOverride = (storageId, path) => gate.future;

    // Hang the feed inside its node lookup: `_feedInFlight` is held for the
    // whole window, and that alone is what protects a legitimate switch.
    unawaited(ctrl.startSession(queue: [_item()], queueIndex: 0));
    await pumpEventQueue();
    expect(ctrl.feedInFlight, isTrue, reason: 'the feed must actually hang');
    expect(ctrl.state.item, isNotNull);

    ctrl.releaseOrphanedTransition();

    expect(ctrl.state.item, isNotNull,
        reason: 'an in-flight feed still owns the switch — never torn down');
    expect(ctrl.state.transitioning, isTrue,
        reason: 'the switch-freeze survives with it');

    // Settle the feed: a null node routes through handleSegmentError, whose
    // `isActive` gate no-ops because this feed never reached the queue.
    gate.complete(null);
    await pumpEventQueue();
    expect(ctrl.feedInFlight, isFalse);

    // The guard is gone and nothing carried the session: the same release
    // now clears it (and stops the anchor timer) without any hook rebuild.
    ctrl.releaseOrphanedTransition();
    expect(ctrl.state.item, isNull);
  });
}

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/background_playback/resolver/vm_tiled_plan.dart';
import 'package:iris/features/background_playback/store/use_background_playback_store.dart';
import 'package:iris/models/file.dart';

/// Session-only per-segment overrides of the tiled plan (plan v3).
///
/// A user adjustment on one inner segment (align dialog pick, mapping-editor
/// save, manual bg switch confirmed by dialog) is remembered for THIS app
/// launch only; every other segment keeps the precomputed tiling.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureStorageChannel, (call) async => null);

  FileItem f(String name) =>
      FileItem(name: name, uri: 'file:///$name', path: [name]);

  group('vmTiledOverrides', () {
    late BackgroundPlaybackStore store;

    setUp(() async {
      store = BackgroundPlaybackStore();
      await store.initialized;
    });

    tearDown(() => store.dispose());

    test('starts empty and records per-segment slots', () {
      expect(store.state.vmTiledOverrides, isEmpty);
      store.recordVmTiledOverride(
        's1',
        const VmTiledSlot(bgIndex: 2, bgOffsetMs: 1500),
      );
      expect(
        store.state.vmTiledOverrides['s1'],
        const VmTiledSlot(bgIndex: 2, bgOffsetMs: 1500),
      );
      // Other segments are untouched.
      expect(store.state.vmTiledOverrides.containsKey('s2'), isFalse);
    });

    test('re-recording the same segment replaces its slot', () {
      store.recordVmTiledOverride(
        's1',
        const VmTiledSlot(bgIndex: 0, bgOffsetMs: 0),
      );
      store.recordVmTiledOverride(
        's1',
        const VmTiledSlot(bgIndex: 1, bgOffsetMs: 300),
      );
      expect(
        store.state.vmTiledOverrides['s1'],
        const VmTiledSlot(bgIndex: 1, bgOffsetMs: 300),
      );
    });

    test('clearVmTiledOverrides drops every override', () {
      store.recordVmTiledOverride(
        's1',
        const VmTiledSlot(bgIndex: 0, bgOffsetMs: 0),
      );
      store.clearVmTiledOverrides();
      expect(store.state.vmTiledOverrides, isEmpty);
    });

    test('overrides are session-only: never persisted, never restored', () {
      store.recordVmTiledOverride(
        's1',
        const VmTiledSlot(bgIndex: 0, bgOffsetMs: 0),
      );
      final normalized =
          BackgroundPlaybackStore.normalizeLoaded(store.state);
      expect(normalized.vmTiledOverrides, isEmpty);
      expect(normalized.vmTiledSeq, 0);
    });

    test('requestTiledTarget selects the file and queues the offset seek',
        () async {
      await store.enableWithQueue([f('a'), f('b')]);
      await store.requestTiledTarget(index: 1, targetMs: 2500);
      expect(store.state.currentIndex, 1);
      expect(store.state.tiledTargetIndex, 1);
      expect(store.state.tiledSeekTargetMs, 2500);
      expect(store.state.tiledSeekSeq, 1);
    });

    test('requestTiledTarget is a no-op while 副音 is off', () async {
      await store.requestTiledTarget(index: 0, targetMs: 100);
      expect(store.state.tiledSeekSeq, 0);
    });

    test('consumeTiledSeek clears the one-shot without touching the queue',
        () async {
      await store.enableWithQueue([f('a'), f('b')]);
      await store.requestTiledTarget(index: 1, targetMs: 2500);
      store.consumeTiledSeek();
      expect(store.state.tiledSeekSeq, 0);
      expect(store.state.tiledTargetIndex, -1);
      expect(store.state.currentIndex, 1);
    });

    test('a user step raises the manual-switch signal for the VM link',
        () async {
      await store.enableWithQueue([f('a'), f('b')]);
      await store.step(forward: true, userInitiated: true);
      expect(store.state.userBgSwitchSeq, 1);
      expect(store.state.userBgSwitchIndex, store.state.currentIndex);
      store.consumeUserBgSwitch();
      expect(store.state.userBgSwitchSeq, 0);
    });

    test('a system step never raises the manual-switch signal', () async {
      await store.enableWithQueue([f('a'), f('b')]);
      await store.step(forward: true);
      expect(store.state.userBgSwitchSeq, 0);
    });

    test('tiled/user-switch signals are session-only', () async {
      await store.enableWithQueue([f('a'), f('b')]);
      await store.requestTiledTarget(index: 1, targetMs: 10);
      await store.step(forward: true, userInitiated: true);
      final normalized =
          BackgroundPlaybackStore.normalizeLoaded(store.state);
      expect(normalized.tiledSeekSeq, 0);
      expect(normalized.tiledTargetIndex, -1);
      expect(normalized.userBgSwitchSeq, 0);
    });
  });
}

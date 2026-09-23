import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/background_playback/model/enum/bg_cross_action.dart';
import 'package:iris/features/background_playback/model/enum/bg_vm_scope_mode.dart';
import 'package:iris/features/background_playback/services/vm_scope_identity.dart';
import 'package:iris/features/background_playback/store/use_background_playback_store.dart';
import 'package:iris/features/virtual_media/interaction/controller/virtual_bg_link.dart';
import 'package:iris/models/file.dart';

/// VM × 副音 rules: the pure switch decision, the 作用范围 identity resolver,
/// and the store fields/AUX rows behind them.
///
/// The 作用范围 card widget tests live in `background_scope_panel_vm_test.dart`
/// — a store-writing test followed by a widget test in the same file leaves the
/// harness awaiting an unresolved store load.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureStorageChannel, (call) async => null);

  group('vmSubAudioSwitchAction', () {
    VmBgSwitchAction decide({
      BgCrossAction itemRule = BgCrossAction.newBg,
      BgCrossAction segmentRule = BgCrossAction.keepPlaying,
      bool applied = true,
      bool segmentChanged = false,
      bool itemChanged = false,
      bool changeWasSeek = false,
      bool lockOwnsSeek = false,
    }) =>
        vmSubAudioSwitchAction(
          itemRule: itemRule,
          segmentRule: segmentRule,
          applied: applied,
          segmentChanged: segmentChanged,
          itemChanged: itemChanged,
          changeWasSeek: changeWasSeek,
          lockOwnsSeek: lockOwnsSeek,
        );

    test('a new list item follows the item rule', () {
      expect(
        decide(itemRule: BgCrossAction.newBg, itemChanged: true),
        VmBgSwitchAction.newBg,
      );
      expect(
        decide(itemRule: BgCrossAction.keepPlaying, itemChanged: true),
        VmBgSwitchAction.none,
      );
    });

    test('a segment switch follows the segment rule', () {
      expect(
        decide(segmentRule: BgCrossAction.newBg, segmentChanged: true),
        VmBgSwitchAction.newBg,
      );
      expect(
        decide(segmentRule: BgCrossAction.keepPlaying, segmentChanged: true),
        VmBgSwitchAction.none,
      );
    });

    test('a genuine item change outranks a simultaneous segment change', () {
      expect(
        decide(
          itemRule: BgCrossAction.keepPlaying,
          segmentRule: BgCrossAction.newBg,
          itemChanged: true,
          segmentChanged: true,
        ),
        VmBgSwitchAction.none,
      );
      expect(
        decide(
          itemRule: BgCrossAction.newBg,
          segmentRule: BgCrossAction.keepPlaying,
          itemChanged: true,
          segmentChanged: true,
        ),
        VmBgSwitchAction.newBg,
      );
    });

    test('the full lock owns a seek-driven switch', () {
      expect(
        decide(
          segmentRule: BgCrossAction.newBg,
          segmentChanged: true,
          changeWasSeek: true,
          lockOwnsSeek: true,
        ),
        VmBgSwitchAction.none,
        reason: 'the fixed-offset mapping already rolled bg for the seek',
      );
      expect(
        decide(
          segmentRule: BgCrossAction.newBg,
          segmentChanged: true,
          changeWasSeek: true,
          lockOwnsSeek: false,
        ),
        VmBgSwitchAction.newBg,
        reason: 'without the lock nobody else maps the seek',
      );
    });

    test('nothing happens when nothing changed', () {
      expect(decide(), VmBgSwitchAction.none);
    });

    test('nothing happens while 副音 is not applied to this media', () {
      // 作用范围 always wins: a scope transition must never also switch tracks.
      expect(
        decide(applied: false, segmentChanged: true, itemChanged: true),
        VmBgSwitchAction.none,
      );
    });
  });

  group('vmScopeIdentityOverride (作用范围 identity)', () {
    const itemKey = 'vm:r|root|#1';

    test('perBlock keeps the physical block identity (default)', () {
      expect(
        vmScopeIdentityOverride(
          vmActive: true,
          vmItemKey: itemKey,
          mode: BgVmScopeMode.perBlock,
        ),
        isNull,
        reason: 'each block IS the current media under 独立块匹配',
      );
    });

    test('wholeVirtual publishes the virtual video identity', () {
      expect(
        vmScopeIdentityOverride(
          vmActive: true,
          vmItemKey: itemKey,
          mode: BgVmScopeMode.wholeVirtual,
        ),
        itemKey,
      );
    });

    test('no active VM session never overrides', () {
      for (final mode in BgVmScopeMode.values) {
        expect(
          vmScopeIdentityOverride(
            vmActive: false,
            vmItemKey: itemKey,
            mode: mode,
          ),
          isNull,
        );
      }
    });

    test('a missing item key never overrides', () {
      expect(
        vmScopeIdentityOverride(
          vmActive: true,
          vmItemKey: null,
          mode: BgVmScopeMode.wholeVirtual,
        ),
        isNull,
      );
      expect(
        vmScopeIdentityOverride(
          vmActive: true,
          vmItemKey: '',
          mode: BgVmScopeMode.wholeVirtual,
        ),
        isNull,
      );
    });

    test('the item key is namespaced so it can never collide with a file key',
        () {
      final key = vmScopeItemKey('r|root|#1');
      expect(key.startsWith(kVmScopeKeyPrefix), isTrue);
      expect(key, 'vm:r|root|#1');
    });

    test('a pinned whole item keeps its identity, a later item falls back',
        () {
      // Unpinned (first sighting) publishes so the caller can pin it.
      expect(
        vmScopeIdentityOverride(
          vmActive: true,
          vmItemKey: itemKey,
          mode: BgVmScopeMode.wholeVirtual,
        ),
        itemKey,
      );
      // The anchored item keeps the whole identity.
      expect(
        vmScopeIdentityOverride(
          vmActive: true,
          vmItemKey: itemKey,
          mode: BgVmScopeMode.wholeVirtual,
          pinnedItemKey: itemKey,
        ),
        itemKey,
      );
      // A later virtual item is NOT the "当时的当前": physical identity.
      expect(
        vmScopeIdentityOverride(
          vmActive: true,
          vmItemKey: 'vm:r|other|#1',
          mode: BgVmScopeMode.wholeVirtual,
          pinnedItemKey: itemKey,
        ),
        isNull,
      );
    });
  });

  group('store', () {
    late BackgroundPlaybackStore store;

    FileItem f(String name) =>
        FileItem(name: name, uri: 'file:///$name', path: [name]);

    setUp(() async {
      store = BackgroundPlaybackStore();
      await store.initialized;
    });

    tearDown(() => store.dispose());

    test('cross-video switches: item defaults newBg, segment keepPlaying',
        () async {
      expect(store.state.bgItemSwitch, BgCrossAction.newBg);
      expect(store.state.bgSegmentSwitch, BgCrossAction.keepPlaying);

      await store.setBgItemSwitch(BgCrossAction.keepPlaying);
      await store.setBgSegmentSwitch(BgCrossAction.newBg);
      expect(store.state.bgItemSwitch, BgCrossAction.keepPlaying);
      expect(store.state.bgSegmentSwitch, BgCrossAction.newBg);
    });

    test('vmSessionActive publishes and is session-only', () {
      expect(store.state.vmSessionActive, isFalse);
      store.setVmSessionActive(true);
      expect(store.state.vmSessionActive, isTrue);
      expect(
        BackgroundPlaybackStore.normalizeLoaded(store.state).vmSessionActive,
        isFalse,
      );
    });

    test('bgVmScopeMode defaults to perBlock (独立块匹配) and is settable',
        () async {
      expect(store.state.bgVmScopeMode, BgVmScopeMode.perBlock);
      await store.setBgVmScopeMode(BgVmScopeMode.wholeVirtual);
      expect(store.state.bgVmScopeMode, BgVmScopeMode.wholeVirtual);
    });

    test('the scope override is session-only and idempotent', () async {
      expect(store.state.vmScopeKeyOverride, isNull);

      store.setVmScopeOverride('vm:r|root|#1');
      expect(store.state.vmScopeKeyOverride, 'vm:r|root|#1');

      // Same value again = no extra notification.
      store.setVmScopeOverride('vm:r|root|#1');
      expect(store.state.vmScopeKeyOverride, 'vm:r|root|#1');

      // Empty clears it (leaving the VM session).
      store.setVmScopeOverride('');
      expect(store.state.vmScopeKeyOverride, isNull);

      // Never persisted: the cold-load normalizer drops it.
      store.setVmScopeOverride('vm:r|root|#1');
      expect(
        BackgroundPlaybackStore.normalizeLoaded(store.state).vmScopeKeyOverride,
        isNull,
      );
    });

    test('bumpVmAlignReset advances the alignment-reset counter', () {
      expect(store.state.vmAlignResetSeq, 0);
      store.bumpVmAlignReset();
      store.bumpVmAlignReset();
      expect(store.state.vmAlignResetSeq, 2);
      expect(
        BackgroundPlaybackStore.normalizeLoaded(store.state).vmAlignResetSeq,
        0,
        reason: 'the reset latch is session state',
      );
    });

    test('requestLockTarget selects the file and queues the seek', () async {
      await store.enableWithQueue([f('a'), f('b')]);
      await store.requestLockTarget(index: 1, targetMs: 5000);

      expect(store.state.currentIndex, 1);
      expect(store.state.lockTargetIndex, 1);
      expect(store.state.lockSeekTargetMs, 5000);
      expect(store.state.lockSeekSeq, 1);

      await store.requestLockTarget(index: 0, targetMs: -3);
      expect(store.state.lockSeekSeq, 2);
      expect(store.state.lockSeekTargetMs, 0,
          reason: 'a negative target clamps to the head');
    });

    test('requestLockTarget is a no-op while 副音 is off', () async {
      await store.requestLockTarget(index: 0, targetMs: 1000);
      expect(store.state.lockSeekSeq, 0);
      expect(store.state.currentIndex, -1);
    });
  });
}

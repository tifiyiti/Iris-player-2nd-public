import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/background_playback/engine/background_scope_logic.dart';
import 'package:iris/features/background_playback/model/enum/bg_apply_scope.dart';
import 'package:iris/features/background_playback/model/enum/bg_quick_panel.dart';
import 'package:iris/features/background_playback/store/use_background_playback_store.dart';
import 'package:iris/models/file.dart';

FileItem _f(String key) =>
    FileItem(name: key, uri: 'file:///$key', path: [key]);

/// 第 4 轮问题 2: the "对当前" toggle must survive a foreground media switch
/// (re-anchor) and must be able to turn back on after a close.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureStorageChannel, (call) async => null);

  bool applied(BackgroundPlaybackStore store, String fgKey) =>
      resolveApplyToCurrent(
        enabled: store.state.enabled,
        applyScope: store.state.applyScope,
        anchorKey: store.state.scopeAnchorKey,
        offMediaKeys: store.state.bgOffMediaKeys,
        fgKey: fgKey,
      );

  late BackgroundPlaybackStore store;

  setUp(() async {
    store = BackgroundPlaybackStore();
    await store.initialized;
  });

  tearDown(() => store.dispose());

  test('media switch away then apply re-anchors and resumes', () async {
    await store.enableWithQueue(
      [_f('a')],
      applyScope: BgApplyScope.currentOnly,
      anchorKey: 'a',
    );
    expect(applied(store, 'a'), isTrue);

    // Foreground moved to b: the run is paused and reads "not applied".
    expect(applied(store, 'b'), isFalse);

    store.applyToCurrent('b');

    expect(store.state.scopeAnchorKey, 'b',
        reason: 'the anchor must follow the media the user applied it to');
    expect(store.state.bgOffMediaKeys, isNot(contains('b')));
    expect(store.state.bgAutoPlay, isTrue);
    expect(applied(store, 'b'), isTrue,
        reason: 'the toggle must be able to turn back on after a switch');
  });

  test('close then apply toggles back on for the same media', () async {
    await store.enableWithQueue(
      [_f('a')],
      applyScope: BgApplyScope.currentOnly,
      anchorKey: 'a',
    );

    store.closeScopeForMedia('a');
    expect(applied(store, 'a'), isFalse);
    expect(store.state.bgAutoPlay, isFalse);

    store.applyToCurrent('a');
    expect(applied(store, 'a'), isTrue);
    expect(store.state.bgAutoPlay, isTrue);
  });

  test('all scope: apply clears the off set without touching the anchor',
      () async {
    await store.enableWithQueue([_f('a')], applyScope: BgApplyScope.all);
    expect(store.state.scopeAnchorKey, isNull);

    store.applyToCurrent('b');
    expect(store.state.scopeAnchorKey, isNull);
    expect(applied(store, 'b'), isTrue);
  });

  test('applyToCurrent is a no-op while 副音 is off', () async {
    // A cold load now arms the run (startArmed default on) — force it off.
    await store.disable();
    expect(store.state.enabled, isFalse);
    store.applyToCurrent('a');
    expect(store.state.bgAutoPlay, isFalse);
    expect(store.state.scopeAnchorKey, isNull);
  });

  test('disable clears the anchor and closes any open quick panel', () async {
    await store.enableWithQueue(
      [_f('a')],
      applyScope: BgApplyScope.currentOnly,
      anchorKey: 'a',
    );
    store.showQuickPanel(BgQuickPanel.scope);
    expect(store.state.openQuickPanel, BgQuickPanel.scope);

    await store.disable();

    expect(store.state.scopeAnchorKey, isNull);
    expect(store.state.openQuickPanel, BgQuickPanel.none);
  });

  test('applyToCurrent(autoplay: false) re-anchors without starting playback',
      () async {
    await store.enableWithQueue(
      [_f('a')],
      applyScope: BgApplyScope.currentOnly,
      anchorKey: 'a',
    );

    store.applyToCurrent('b', autoplay: false);

    expect(store.state.scopeAnchorKey, 'b');
    expect(applied(store, 'b'), isTrue);
    expect(store.state.bgAutoPlay, isFalse,
        reason: 'a paused foreground is not force-played when re-anchoring');
  });

  test('enableWithQueue(autoplay: false) arms the run paused', () async {
    await store.enableWithQueue([_f('a')], autoplay: false);

    expect(store.state.enabled, isTrue);
    expect(store.state.gateOpen, isTrue);
    expect(store.state.bgAutoPlay, isFalse);
  });

  test('resumeForScope(play: false) stays paused after returning to the anchor',
      () async {
    await store.enableWithQueue(
      [_f('a')],
      applyScope: BgApplyScope.currentOnly,
      anchorKey: 'a',
    );
    store.pauseForScope();

    store.resumeForScope(play: false);

    expect(store.state.bgAutoPlay, isFalse);
  });
}

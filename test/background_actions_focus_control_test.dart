import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/background_playback/actions/background_playback_actions.dart';
import 'package:iris/features/background_playback/model/enum/control_target.dart';
import 'package:iris/features/background_playback/store/use_background_playback_store.dart';
import 'package:iris/models/file.dart';
import 'package:zustand/zustand.dart';

/// 第 4 轮问题 3: starting 副音 must actually hand over the controls.
///
/// Regression: `startWithCandidates` used to declare `focusControl = false` and
/// pass it explicitly, overriding the store's `autoFocusControl` preference —
/// so NO activation path ever switched the control target.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureStorageChannel, (call) async => null);

  tearDown(() => StoreLocator().delete(BackgroundPlaybackStore));

  final candidates = [
    FileItem(name: 'bg.mp3', uri: 'file:///bg.mp3', path: const ['bg.mp3']),
  ];

  test('startWithCandidates honours the autoFocusControl preference (on)', () async {
    final bg = useBackgroundPlaybackStore();
    await bg.initialized;
    expect(bg.state.autoFocusControl, isTrue, reason: 'default is on');

    await BackgroundPlaybackActions.startWithCandidates(
      candidates,
      replace: false,
    );

    expect(bg.state.enabled, isTrue);
    expect(bg.state.controlTarget, ControlTarget.background,
        reason: '自动切换控制 must reach the store default');
  });

  test('startWithCandidates honours the autoFocusControl preference (off)',
      () async {
    final bg = useBackgroundPlaybackStore();
    await bg.initialized;
    await bg.setAutoFocusControl(false);

    await BackgroundPlaybackActions.startWithCandidates(
      candidates,
      replace: false,
    );

    expect(bg.state.controlTarget, ControlTarget.foreground,
        reason: 'the meta switch must be able to keep the video controllable');
  });

  test('an explicit override still beats the preference', () async {
    final bg = useBackgroundPlaybackStore();
    await bg.initialized;
    await bg.setAutoFocusControl(false);

    await BackgroundPlaybackActions.startWithCandidates(
      candidates,
      replace: false,
      focusControl: true,
    );

    expect(bg.state.controlTarget, ControlTarget.background);
  });
}

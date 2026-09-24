import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/background_playback/model/enum/control_target.dart';
import 'package:iris/features/background_playback/store/use_background_playback_store.dart';
import 'package:iris/models/player.dart';
import 'package:iris/pages/player/control_bar/control_bar_slider.dart';
import 'package:iris/store/use_player_ui_store.dart';
import 'package:provider/provider.dart';

/// The 副音 control view reports `buffer == duration` (no secondary buffer
/// tracking — see `BackgroundPlaybackEngine.asMediaPlayer`) while the published
/// seek window can cap the axis BELOW the file duration. The buffer must be
/// clamped into the slider's own `[min, max]` or Flutter's `Slider` asserts
/// `secondaryTrackValue` out of range — the reported red-screen crash.
///
/// Both scenarios share ONE testWidgets on purpose: the background store must
/// stay inside a single FakeAsync zone (deleting and recreating it across zones
/// trips `StoreLocator`'s closed-change stream).
MediaPlayer _player({
  required Duration position,
  required Duration duration,
  required Duration buffer,
}) {
  return MediaPlayer(
    isInitializing: false,
    isPlaying: false,
    externalSubtitles: const [],
    position: position,
    duration: duration,
    buffer: buffer,
    width: 16,
    height: 9,
    saveProgress: () async {},
    play: () async {},
    pause: () async {},
    backward: (_) async {},
    forward: (_) async {},
    stepBackward: () async {},
    stepForward: () async {},
    seek: (_) async {},
  );
}

Widget _harness(MediaPlayer player) {
  return StoreScope(
    child: Provider<MediaPlayer>.value(
      value: player,
      child: const MaterialApp(
        home: Scaffold(body: Center(child: ControlBarSlider())),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The background store's `initialized` gate reads legacy secure storage.
  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureStorageChannel, (call) async => null);

  testWidgets('副音 window caps keep buffer/value inside the Slider bounds',
      (tester) async {
    usePlayerUiStore().updateIsShowControl(true);
    final bg = useBackgroundPlaybackStore();
    await bg.initialized;

    // duration 60s, buffer == duration (how the bg view reports it); the window
    // ceiling (20s) is below the file duration -> the old code asserted
    // `secondaryTrackValue` (60000) out of [0, 20000].
    bg.set(bg.state.copyWith(
      enabled: true,
      gateOpen: true,
      controlTarget: ControlTarget.background,
      bgSeekFloorLocalMs: 0,
      bgSeekCeilingLocalMs: 20000,
    ));
    await tester.pumpWidget(_harness(_player(
      position: const Duration(seconds: 10),
      duration: const Duration(seconds: 60),
      buffer: const Duration(seconds: 60),
    )));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final capped = tester.widget<Slider>(find.byType(Slider));
    expect(capped.max, 20000);
    expect(capped.secondaryTrackValue, isNotNull);
    expect(capped.secondaryTrackValue! >= capped.min, isTrue);
    expect(capped.secondaryTrackValue! <= capped.max, isTrue);
    expect(capped.value >= capped.min && capped.value <= capped.max, isTrue);

    // An EMPTY window (floor at the file end) used to hit
    // `clamp(sliderMin + 1, max)` with lower > upper -> ArgumentError.
    bg.set(bg.state.copyWith(
      bgSeekFloorLocalMs: 60000,
      bgSeekCeilingLocalMs: 60000,
    ));
    await tester.pump();

    expect(tester.takeException(), isNull);
    final empty = tester.widget<Slider>(find.byType(Slider));
    expect(empty.min < empty.max, isTrue);
    expect(empty.value >= empty.min && empty.value <= empty.max, isTrue);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/background_playback/model/enum/control_target.dart';
import 'package:iris/features/background_playback/store/use_background_playback_store.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/player.dart';
import 'package:iris/pages/player/control_bar/control_bar_slider.dart';
import 'package:iris/pages/player/overlays/minimal_progress_overlay.dart';
import 'package:iris/store/use_player_ui_store.dart';
import 'package:provider/provider.dart';

/// The bottom minimal progress overlay (`ControlBarSlider(disabled: true)`) is a
/// passive foreground readout with no control ability. While the shared controls
/// target 副音 its slider previously applied the bg file's local-axis seek window
/// (floor/ceiling) against the FOREGROUND duration, tripping the slider's range
/// assertions (red-text bug). It must ignore the control target entirely and
/// keep the ordinary foreground playback behavior.
///
/// Regression lock: with bg owning the controls, the display-only slider keeps
/// the foreground range (min 0 / max fg duration) and never throws.

MediaPlayer _player() {
  return MediaPlayer(
    isInitializing: false,
    isPlaying: false,
    externalSubtitles: const [],
    position: const Duration(seconds: 12),
    duration: const Duration(hours: 1),
    buffer: Duration.zero,
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

Widget _harness(Widget child) {
  return StoreScope(
    child: Provider<MediaPlayer>.value(
      value: _player(),
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: Center(child: child)),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureStorageChannel, (call) async => null);

  testWidgets('display-only progress bar ignores the bg control target',
      (tester) async {
    // Point the shared controls at 副音 and publish a seek window whose values
    // only make sense on the BG file's local axis (10 min floor / 20 min
    // ceiling). Applied against the 1h foreground this used to break the
    // slider's range assertions.
    final bg = useBackgroundPlaybackStore();
    await bg.initialized;
    bg.set(bg.state.copyWith(
      enabled: true,
      gateOpen: true,
      controlTarget: ControlTarget.background,
      bgSeekFloorLocalMs: 600000, // 10 min
      bgSeekCeilingLocalMs: 1200000, // 20 min
    ));
    expect(bg.state.bgOwnsControls, isTrue);

    // ── Phase A: display-only slider keeps the foreground range ──
    await tester.pumpWidget(_harness(const ControlBarSlider(disabled: true)));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull,
        reason: 'display-only slider must not throw while 副音 owns controls');

    final Slider slider = tester.widget(find.byType(Slider));
    // Foreground range, not the bg window (would be 600000..1200000).
    expect(slider.min, 0.0);
    expect(slider.max, const Duration(hours: 1).inMilliseconds.toDouble());
    // Foreground buffer; the old code clamped it only to [0, max] and could drop
    // it below `min`, failing the Slider assertion.
    expect(slider.secondaryTrackValue, 0.0);

    // ── Phase B: the minimal overlay still renders the foreground ──
    usePlayerUiStore().updateIsShowProgress(true);
    usePlayerUiStore().updateIsShowControl(false);
    await tester.pumpWidget(_harness(MinimalProgressOverlay(
      title: 'sample',
      file: const FileItem(name: 'a.mp4', uri: 'file:///a.mp4'),
    )));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull,
        reason: 'minimal overlay must render without the red-text error');
    expect(find.byType(Slider), findsOneWidget);
    expect(find.textContaining(' / '), findsOneWidget,
        reason: 'the overlay still shows the foreground position/duration');

    // Restore global UI defaults for sibling tests in the same isolate.
    usePlayerUiStore().updateIsShowProgress(false);
    usePlayerUiStore().updateIsShowControl(false);
  });
}

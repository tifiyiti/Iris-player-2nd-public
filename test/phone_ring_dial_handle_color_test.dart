import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/phone/one_handed_scrubber/view/phone_ring_dial_scrubber.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/player.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:provider/provider.dart';

// The two drag thumbs and the two ring-wedge numerals are the dial's primary
// affordance: they must read at a glance over ANY palette or video frame, so
// they are ALWAYS white (never palette/theme-derived). This suite locks that
// contract by painting the dial with a deliberately hostile accent (red) and
// the rainbow palette, then inspecting the recorded canvas for white circles.

MediaPlayer _player({
  required Duration position,
  required Duration duration,
}) {
  return MediaPlayer(
    isInitializing: false,
    isPlaying: false,
    externalSubtitles: const [],
    position: position,
    duration: duration,
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

Widget _harness(MediaPlayer player) {
  return StoreScope(
    child: Provider<MediaPlayer>.value(
      value: player,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 240,
              height: 210,
              child: PhoneRingDialScrubber(
                showControl: () {},
                // Hostile accent: the white-thumb contract must ignore it.
                color: Colors.red,
                isLeftHanded: false,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Finder _dialPainterFinder() => find.byWidgetPredicate(
      (Widget w) =>
          w is CustomPaint &&
          w.painter != null &&
          w.painter.runtimeType.toString() == '_DialPainter',
    );

bool _isWhiteCircle(Symbol method, List<dynamic> arguments) {
  if (method != #drawCircle || arguments.length != 3) return false;
  return (arguments[2] as Paint).color == Colors.white;
}

void main() {
  test('handle color is fixed opaque white with a dark legibility shadow', () {
    expect(kDialHandleColor, Colors.white);
    expect(kDialHandleShadows, isNotEmpty);
    expect(kDialHandleShadows.every((Shadow s) => s.color.a > 0.5), isTrue);
  });

  testWidgets('both drag thumbs paint white even with a red accent + rainbow',
      (tester) async {
    await useAppStore().updateRingDialPalette(RingDialPalette.rainbow);
    // Pin the legacy 210px ring geometry so a chunk ring exists (36-min media
    // chunks into many blocks → chunk ring + its thumb are painted).
    await useAppStore().updateRingDialHeightPct(1.0);
    await useAppStore().updateRingDialRingSlotT(0.85);

    await tester.pumpWidget(_harness(_player(
      position: Duration.zero,
      duration: const Duration(minutes: 36),
    )));
    await tester.pumpAndSettle();

    expect(_dialPainterFinder(), findsOneWidget);
    // Two white filled circles: the progress-ring thumb and the chunk-ring
    // thumb. Dark halo circles may be interleaved and are skipped by
    // `something`.
    expect(
      _dialPainterFinder(),
      paints
        ..something(_isWhiteCircle)
        ..something(_isWhiteCircle),
    );
  });
}

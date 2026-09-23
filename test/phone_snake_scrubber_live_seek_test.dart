import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/phone/one_handed_scrubber/view/phone_snake_scrubber.dart';
import 'package:iris/models/player.dart';
import 'package:provider/provider.dart';

MediaPlayer _recordingPlayer({
  required void Function(Duration target) onSeek,
  required void Function() onPause,
}) {
  return MediaPlayer(
    isInitializing: false,
    isPlaying: false,
    externalSubtitles: const [],
    position: Duration.zero,
    duration: const Duration(seconds: 60),
    buffer: Duration.zero,
    width: 16,
    height: 9,
    saveProgress: () async {},
    play: () async {},
    pause: () async => onPause(),
    backward: (_) async {},
    forward: (_) async {},
    stepBackward: () async {},
    stepForward: () async {},
    seek: (Duration t) async => onSeek(t),
  );
}

Widget _harness(MediaPlayer player) {
  return StoreScope(
    child: Provider<MediaPlayer>.value(
      value: player,
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              height: 340,
              child: PhoneSnakeScrubber(showControl: () {}, color: Colors.white, isLeftHanded: false),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  // Layout fixture (compact budget): panel 320×340 ⇒ button reserve 96,
  // fittedTracksH = min(340-20-96, 220) = 220 ⇒ axisH 44, r 22.
  // Absolute bar center rows: y = 20 + 44·(k+0.5) → 42 / 86 / 130 / 174 / 218.
  testWidgets('snake drag emits throttled live seek while moving and commits on release', (tester) async {
    final List<Duration> seeks = <Duration>[];
    int pauses = 0;
    final MediaPlayer player = _recordingPlayer(
      onSeek: (Duration t) => seeks.add(t),
      onPause: () => pauses++,
    );

    await tester.pumpWidget(_harness(player));

    final Offset origin = tester.getTopLeft(find.byType(PhoneSnakeScrubber));
    final TestGesture g = await tester.startGesture(origin + const Offset(80, 42));
    await tester.pump();
    expect(seeks, isEmpty, reason: 'touch alone must not seek yet');

    await g.moveBy(const Offset(60, 0));
    await tester.pump(); // crossing slop claims the arena: pan starts here
    await g.moveBy(const Offset(60, 0));
    await tester.pump();
    expect(seeks.length, 1, reason: 'first on-line pan update emits a live seek');

    await g.moveBy(const Offset(60, 0));
    await tester.pump();
    expect(seeks.length, 1, reason: 'rapid movements stay throttled within the interval');

    await g.up();
    await tester.pump();
    expect(seeks.length, 2, reason: 'release commits the final precise seek');
    expect(seeks.last.inMilliseconds, greaterThan(seeks.first.inMilliseconds));

    final TestGesture g2 = await tester.startGesture(origin + const Offset(80, 130));
    await tester.pump();
    await g2.moveBy(const Offset(40, 0));
    await tester.pump();
    await g2.moveBy(const Offset(40, 0));
    await tester.pump();
    expect(seeks.length, 3, reason: 'a fresh drag session re-arms the live-seek throttle');
    await g2.up();
    await tester.pump();

    expect(pauses, greaterThanOrEqualTo(1));
  });
}

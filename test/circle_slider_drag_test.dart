import 'dart:math' as m;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/models/player.dart';
import 'package:iris/pages/player/control_bar/control_bar_widgets/control_bar_circle_slider.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_scrub_drag_store.dart';
import 'package:provider/provider.dart';

/// The classic circle slider now shares the ring dial's drag contract: a drag
/// always engages, live seeks are throttled, and the release ALWAYS commits the
/// final value (a throttled tail tick used to be dropped).
class _Rec {
  final List<Duration> seeks = <Duration>[];

  MediaPlayer player() => MediaPlayer(
        isInitializing: false,
        isPlaying: false,
        externalSubtitles: const [],
        position: const Duration(minutes: 10),
        duration: const Duration(minutes: 60),
        buffer: Duration.zero,
        width: 16,
        height: 9,
        saveProgress: () async {},
        play: () async {},
        pause: () async {},
        backward: (int s) async {},
        forward: (int s) async {},
        stepBackward: () async {},
        stepForward: () async {},
        seek: (Duration t) async => seeks.add(t),
      );
}

Widget _harness(_Rec rec) {
  return StoreScope(
    child: Provider<MediaPlayer>.value(
      value: rec.player(),
      child: const MaterialApp(
        home: Scaffold(
          body: Center(
            child: ControlBarCircleSlider(
              minSize: 200,
              maxSize: 200,
              circleScale: 1.0,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('circle slider: drag engages anywhere, throttles and commits',
      (tester) async {
    final _Rec rec = _Rec();
    await useAppStore().updateAutoPlay(false);
    await tester.pumpWidget(_harness(rec));
    await tester.pumpAndSettle();

    final Offset center = tester.getCenter(find.byType(ControlBarCircleSlider));
    // radius = size/2 - stroke(4) = 96 at size 200; press INSIDE the ring
    // (dist 0..) which the old `isPointOnRing` start check rejected.
    Offset prev = center + const Offset(50, 0);
    final TestGesture g = await tester.startGesture(prev);
    await tester.pump();

    // Five rapid moves within one throttle window (DateTime.now-based).
    for (int i = 1; i <= 5; i++) {
      final Offset p = center +
          Offset(96 * _cos(i * 30.0), 96 * _sin(i * 30.0));
      await g.moveBy(p - prev);
      prev = p;
      await tester.pump();
    }
    expect(useScrubDragStore().state.isScrubbing, isTrue,
        reason: 'a drag starting off the ring band must still arm the session');
    final int duringDrag = rec.seeks.length;
    expect(duringDrag, lessThanOrEqualTo(2),
        reason: 'live seeks must be throttled (got $duringDrag)');

    await g.up();
    await tester.pump();
    expect(useScrubDragStore().state.isScrubbing, isFalse,
        reason: 'release clears the scrub session');
    expect(rec.seeks, isNotEmpty,
        reason: 'the release must commit the final value');
    expect(rec.seeks.length, duringDrag + 1,
        reason: 'exactly one commit seek on release');

    // ── Phase 2: a CANCELLED gesture must not latch the session ──
    rec.seeks.clear();
    Offset prev2 = center + const Offset(50, 0);
    final TestGesture g2 = await tester.startGesture(prev2);
    await tester.pump();
    final Offset p2 = center + const Offset(0, 96);
    await g2.moveBy(p2 - prev2);
    prev2 = p2;
    await tester.pump();
    expect(useScrubDragStore().state.isScrubbing, isTrue);
    await g2.cancel();
    await tester.pump();
    expect(useScrubDragStore().state.isScrubbing, isFalse,
        reason: 'a cancelled gesture must not latch the scrub session');
  });
}

double _cos(double deg) => m.cos(deg * m.pi / 180);
double _sin(double deg) => m.sin(deg * m.pi / 180);

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/phone/one_handed_scrubber/view/phone_snake_scrubber.dart';
import 'package:iris/models/player.dart';
import 'package:provider/provider.dart';

// Layout fixture: panel 320×340. With the compact sizing budget the snake
// area is fittedTracksH = min(340-20-96, 220) = 220 ⇒ axisH = 44, r = 22.
// Bar center rows (widget coords): y = 20 + 44·(k+0.5) → 42/86/130/174/218.
// Right-handed: trackLeft = r = 22; axisW = 320-28-2r = 248 → bars x∈[22,270].
// The geometry-dependent assertions below read sizes from the live painter,
// so they stay valid if the budget constants are tuned later.
//
// All phases live in ONE testWidgets on one long-lived tree: flutter_zustand's
// async StoreScope teardown races with the next test's first build and can
// hand it an already-closed store singleton, and awaiting its reset inside
// FakeAsync stalls. Same-type repumps reuse the scope, so phases are safe.

MediaPlayer _player({
  required Duration position,
  required void Function(Duration target) onSeek,
}) {
  return MediaPlayer(
    isInitializing: false,
    isPlaying: false,
    externalSubtitles: const [],
    position: position,
    duration: const Duration(seconds: 60),
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
    seek: (Duration t) async => onSeek(t),
  );
}

Widget _harness(MediaPlayer player, {bool isLeftHanded = false}) {
  return StoreScope(
    child: Provider<MediaPlayer>.value(
      value: player,
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              height: 340,
              child: PhoneSnakeScrubber(showControl: () {}, color: Colors.white, isLeftHanded: isLeftHanded),
            ),
          ),
        ),
      ),
    ),
  );
}

dynamic _painterOfType(WidgetTester tester, String typeName) {
  for (final CustomPaint cp in tester.widgetList<CustomPaint>(find.byType(CustomPaint))) {
    if (cp.painter != null && cp.painter!.runtimeType.toString() == typeName) {
      return cp.painter;
    }
  }
  fail('Painter $typeName not found');
}

dynamic _snakePainter(WidgetTester tester) => _painterOfType(tester, '_SnakePainter');

Offset _midBar(WidgetTester tester, Offset origin) {
  final dynamic geo = (_snakePainter(tester).geometry as dynamic);
  final double axisH = (geo.fittedTracksH as double) / 5;
  return origin + Offset(80, 20 + axisH * 2.5);
}

void main() {
  testWidgets('snake compact sizing, floating-freeze paint, signed fine extensions', (tester) async {
    // ── Phase 1: floating fine adjust freezes snake paint; release jumps ──
    final List<Duration> seeks = <Duration>[];
    MediaPlayer player = _player(position: Duration.zero, onSeek: seeks.add);
    await tester.pumpWidget(_harness(player));

    final Offset origin = tester.getTopLeft(find.byType(PhoneSnakeScrubber));

    // On-line drag on the middle bar to establish a nonzero anchor.
    TestGesture g = await tester.startGesture(_midBar(tester, origin));
    await tester.pump();
    await g.moveBy(const Offset(60, 0));
    await tester.pump(); // pan starts
    await g.moveBy(const Offset(60, 0));
    await tester.pump();
    expect(seeks, isNotEmpty, reason: 'on-line drag live-seeks');
    final Duration frozenAt = seeks.last;

    // Hold still long enough to trigger hold-on.
    await tester.pump(const Duration(milliseconds: 450));

    // Vertical slide enters locked floating adjust (dy must dominate the
    // accumulated horizontal offset or hold-on reads it as a cancel).
    await g.moveBy(const Offset(0, -90));
    await tester.pump();
    await g.moveBy(const Offset(0, -30));
    await tester.pump();

    // Snake paint stays frozen at the hold-on anchor while fine target moved.
    expect(_snakePainter(tester).preview as Duration, frozenAt,
        reason: 'snake progress+thumb stay locked at the hold-on anchor during floating');

    // Release commits; painted value jumps to the committed target.
    await g.up();
    await tester.pump();
    final Duration committed = seeks.last;
    expect(committed, isNot(frozenAt), reason: 'fine adjust changed the committed target');
    player = _player(position: committed, onSeek: seeks.add);
    await tester.pumpWidget(_harness(player));
    expect(_snakePainter(tester).preview as Duration, committed,
        reason: 'after release the snake paint jumps to the committed position');

    // ── Phase 2: floating axis paints an extension with direction sign ──
    player = _player(position: Duration.zero, onSeek: (_) {});
    await tester.pumpWidget(_harness(player));

    g = await tester.startGesture(_midBar(tester, origin));
    await tester.pump();
    await g.moveBy(const Offset(60, 0));
    await tester.pump(); // pan starts
    await tester.pump(const Duration(milliseconds: 450));

    // First vertical move only ENTERS floating (no preview update yet);
    // dy must dominate the horizontal offset or hold-on cancels instead.
    await g.moveBy(const Offset(0, 100));
    await tester.pump();
    await g.moveBy(const Offset(0, 20));
    await tester.pump();
    final dynamic floatPainter = _painterOfType(tester, '_FloatAxisPainter');
    expect((floatPainter.extPx as double), greaterThan(0),
        reason: 'downward slide extends toward 100% with positive extPx');

    // Drag UP past the anchor = backward (toward 0%) → negative extension.
    await g.moveBy(const Offset(0, -300));
    await tester.pump();
    expect((_painterOfType(tester, '_FloatAxisPainter').extPx as double), lessThan(0),
        reason: 'upward slide past the anchor extends toward 0% with negative extPx');

    await g.up();
    await tester.pump();

    // ── Phase 3: serpentine bulges stay inside the panel on both hands ──
    for (final bool leftHanded in <bool>[false, true]) {
      await tester.pumpWidget(_harness(_player(position: Duration.zero, onSeek: (_) {}), isLeftHanded: leftHanded));
      final dynamic geo = (_snakePainter(tester).geometry as dynamic);
      final double trackLeft = geo.trackLeft as double;
      final double axisW = geo.axisW as double;
      final double r = (geo.fittedTracksH as double) / 10;

      final double leftBound = leftHanded ? 28.0 : 0.0;
      final double rightBound = leftHanded ? 320.0 : 320.0 - 28.0;
      expect(trackLeft - r, greaterThanOrEqualTo(leftBound - 0.01),
          reason: 'left-hand ${leftHanded ? 'odd' : 'even'} arc bulge must not cross the strip side');
      expect(trackLeft + axisW + r, lessThanOrEqualTo(rightBound + 0.01),
          reason: 'right-side arc bulge must not leave the panel');
    }

    // ── Phase 4: fixed strip offset colors by sign around the anchor tick ──
    // Nonzero start position so backward adjust stays inside the media range.
    player = _player(position: const Duration(seconds: 20), onSeek: (_) {});
    await tester.pumpWidget(_harness(player));

    g = await tester.startGesture(origin + const Offset(306, 130));
    await tester.pump();

    // Drag DOWN on the strip → forward (positive delta).
    await g.moveBy(const Offset(0, 60));
    await tester.pump();
    final dynamic p1 = _painterOfType(tester, '_FixedStripPainter');
    expect(p1.dotV as double, greaterThan(0));
    expect(p1.backColor, isNotNull, reason: 'backward color must exist even when unused');

    // Drag UP well past the start → backward (negative delta).
    await g.moveBy(const Offset(0, -140));
    await tester.pump();
    expect((_painterOfType(tester, '_FixedStripPainter').dotV as double), lessThan(0));

    await g.up();
    await tester.pump();
  });
}

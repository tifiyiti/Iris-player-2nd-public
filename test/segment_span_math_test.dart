import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/background_playback/model/enum/bg_sticky_consume.dart';
import 'package:iris/features/background_playback/resolver/segment_span_math.dart';
import 'package:iris/utils/format_duration_hms.dart';

void main() {
  group('formatDurationHms', () {
    test('renders mm:ss under an hour and h:mm:ss at/over an hour', () {
      expect(formatDurationHms(Duration.zero), '00:00');
      expect(formatDurationHms(const Duration(seconds: 65)), '01:05');
      expect(formatDurationHms(const Duration(minutes: 59, seconds: 59)),
          '59:59');
      expect(formatDurationHms(const Duration(hours: 1)), '1:00:00');
      expect(formatDurationHms(const Duration(hours: 1, seconds: 1)),
          '1:00:01');
      expect(formatDurationHms(const Duration(hours: 12, minutes: 34, seconds: 56)),
          '12:34:56');
      // Sign is the caller's concern.
      expect(formatDurationHms(const Duration(seconds: -65)), '01:05');
    });
  });

  group('SegmentSpanMath bounds', () {
    test('A floor follows bg 00:00 only when bg leads the foreground', () {
      expect(SegmentSpanMath.minFgStartMs(0), 0);
      expect(SegmentSpanMath.minFgStartMs(-30000), 30000);
      expect(SegmentSpanMath.minFgStartMs(30000), 0);
    });

    test('B ceiling is the tighter of foreground end and bg tail', () {
      expect(
        SegmentSpanMath.maxFgEndMs(bgOffsetMs: 0, fgDurMs: 100000, bgDurMs: 40000),
        40000,
      );
      expect(
        SegmentSpanMath.maxFgEndMs(
            bgOffsetMs: -30000, fgDurMs: 100000, bgDurMs: 40000),
        70000,
      );
      expect(
        SegmentSpanMath.maxFgEndMs(bgOffsetMs: 0, fgDurMs: 100000, bgDurMs: 0),
        100000,
      );
    });
  });

  group('SegmentSpanMath clamp', () {
    test('pulls A in to the bg 00:00 floor and B to the bg tail', () {
      const raw = SegmentSpan(
          fgStartMs: 0, fgEndMs: 90000, bgOffsetMs: -30000);
      final out = SegmentSpanMath.clamp(raw, fgDurMs: 100000, bgDurMs: 40000);
      expect(out.fgStartMs, 30000);
      expect(out.fgEndMs, 70000);
      expect(out.lengthMs, 40000);
    });

    test('degenerate domain collapses instead of inverting', () {
      const raw = SegmentSpan(fgStartMs: 0, fgEndMs: 5000, bgOffsetMs: 0);
      final out = SegmentSpanMath.clamp(raw, fgDurMs: 100000, bgDurMs: 100);
      expect(out.fgStartMs, 0);
      expect(out.lengthMs, 0);
    });
  });

  group('SegmentSpanMath drag (hard stops)', () {
    test('A with no lead left carries the whole window toward the head', () {
      const span = SegmentSpan(fgStartMs: 30000, fgEndMs: 70000, bgOffsetMs: -30000);
      final out = SegmentSpanMath.dragStart(span, 0,
          fgDurMs: 100000, bgDurMs: 40000, minSpanMs: kDefaultMinSegmentSpanMs);
      // lead == 0 (bgStart = 0): A cannot discard more, so the window
      // translates left and bgStart stays pinned at 0.
      expect(out.fgStartMs, 0);
      expect(out.fgEndMs, 40000);
      expect(out.bgOffsetMs, 0);
      expect(out.bgStartMs, 0);
      expect(out.bgEndMs, 40000);
    });

    test('B consumes its tail then carries the window toward the end', () {
      const span = SegmentSpan(fgStartMs: 0, fgEndMs: 30000, bgOffsetMs: 0);
      final out = SegmentSpanMath.dragEnd(span, 90000,
          fgDurMs: 100000, bgDurMs: 40000, minSpanMs: kDefaultMinSegmentSpanMs);
      // 10s of tail consumed first, then the window carries; bg stays [0, 40s].
      expect(out.fgEndMs, 90000);
      expect(out.fgStartMs, 50000);
      expect(out.bgEndMs, 40000);
      expect(out.bgStartMs, 0);
    });

    test('B never exceeds the foreground duration (bg longer than fg)', () {
      const span = SegmentSpan(fgStartMs: 0, fgEndMs: 30000, bgOffsetMs: 0);
      final out = SegmentSpanMath.dragEnd(span, 900000,
          fgDurMs: 60000, bgDurMs: 600000, minSpanMs: kDefaultMinSegmentSpanMs);
      expect(out.fgEndMs, 60000);
    });

    test('A cannot pass B minus the minimum span', () {
      const span = SegmentSpan(fgStartMs: 10000, fgEndMs: 20000);
      final out = SegmentSpanMath.dragStart(span, 25000,
          fgDurMs: 100000, bgDurMs: 0, minSpanMs: kDefaultMinSegmentSpanMs);
      expect(out.fgStartMs, 20000 - kMinSegmentSpanMs);
      expect(out.fgEndMs, 20000);
    });

    test('A may cross the old centre (P is hidden while A/B drag)', () {
      const span = SegmentSpan(fgStartMs: 10000, fgEndMs: 30000);
      final out = SegmentSpanMath.dragStart(span, 25000,
          fgDurMs: 100000, bgDurMs: 0, minSpanMs: kDefaultMinSegmentSpanMs);
      expect(out.fgStartMs, 25000);
      expect(out.fgEndMs, 30000);
    });

    test('A inward always creates a lead, even when it was already 0', () {
      const span = SegmentSpan(fgStartMs: 30000, fgEndMs: 70000, bgOffsetMs: -30000);
      final out = SegmentSpanMath.dragStart(span, 40000,
          fgDurMs: 100000, bgDurMs: 40000, minSpanMs: kDefaultMinSegmentSpanMs);
      expect(out.fgStartMs, 40000);
      expect(out.bgOffsetMs, -30000);
      expect(out.bgStartMs, 10000, reason: 'lead grew from 0 to 10s');
    });

    test('A outward spends the lead before carrying', () {
      const span = SegmentSpan(fgStartMs: 30000, fgEndMs: 50000, bgOffsetMs: -20000);
      // lead = A + off = 10s.
      final out = SegmentSpanMath.dragStart(span, 25000,
          fgDurMs: 100000, bgDurMs: 40000, minSpanMs: kDefaultMinSegmentSpanMs);
      expect(out.fgStartMs, 25000);
      expect(out.fgEndMs, 50000, reason: 'B stays while lead is consumed');
      expect(out.bgStartMs, 5000, reason: 'lead shrank to 5s');
    });

    test('a smaller minimum span allows a tighter window', () {
      const span = SegmentSpan(fgStartMs: 10000, fgEndMs: 20000);
      final out = SegmentSpanMath.dragStart(span, 25000,
          fgDurMs: 100000, bgDurMs: 0, minSpanMs: 100);
      expect(out.fgStartMs, 19900);
      expect(out.fgEndMs, 20000);
    });
  });

  group('SegmentSpanMath slideBgWindow (P = alignment offset)', () {
    test('changes the offset and leaves A/B alone when room exists', () {
      const span = SegmentSpan(fgStartMs: 30000, fgEndMs: 50000, bgOffsetMs: -30000);
      final out = SegmentSpanMath.slideBgWindow(span, 10000,
          fgDurMs: 100000, bgDurMs: 40000);
      expect(out.bgOffsetMs, -20000);
      expect(out.fgStartMs, 30000);
      expect(out.fgEndMs, 50000);
      expect(out.bgStartMs, 10000);
    });

    test('the user example: bg lagging 30s pushes the A floor to 30s', () {
      // Aligned at 00:00 with A at 0..20s; shifting bg 30s later (off=-30s)
      // means fg 0..30s maps before bg 00:00 — no bg content there at all.
      const span = SegmentSpan(fgStartMs: 0, fgEndMs: 20000, bgOffsetMs: 0);
      final out = SegmentSpanMath.slideBgWindow(span, -30000,
          fgDurMs: 100000, bgDurMs: 40000);
      expect(out.bgOffsetMs, -30000);
      expect(out.fgStartMs, greaterThanOrEqualTo(30000));
      expect(out.bgStartMs, greaterThanOrEqualTo(0));
    });

    test('the range follows the offset back (non-destructive from a reference)',
        () {
      const ref = SegmentSpan(fgStartMs: 0, fgEndMs: 20000, bgOffsetMs: 0);
      final away = SegmentSpanMath.slideBgWindow(ref, -30000,
          fgDurMs: 100000, bgDurMs: 40000);
      expect(away.fgStartMs, 30000);
      // Dragging back from the SAME reference restores the original window.
      final back = SegmentSpanMath.slideBgWindow(ref, 0,
          fgDurMs: 100000, bgDurMs: 40000);
      expect(back, ref);
    });

    test('is incremental against the live span', () {
      const span = SegmentSpan(fgStartMs: 30000, fgEndMs: 50000, bgOffsetMs: -30000);
      final once = SegmentSpanMath.slideBgWindow(span, 5000,
          fgDurMs: 100000, bgDurMs: 40000);
      final twice = SegmentSpanMath.slideBgWindow(once, 5000,
          fgDurMs: 100000, bgDurMs: 40000);
      expect(twice.bgOffsetMs, -20000);
    });

    test('hard-stops so the bg window stays inside the bg file', () {
      const span = SegmentSpan(fgStartMs: 30000, fgEndMs: 50000, bgOffsetMs: -30000);
      final head = SegmentSpanMath.slideBgWindow(span, -100000,
          fgDurMs: 100000, bgDurMs: 40000);
      expect(head.bgStartMs, greaterThanOrEqualTo(0));
      final tail = SegmentSpanMath.slideBgWindow(span, 100000,
          fgDurMs: 100000, bgDurMs: 40000);
      expect(tail.bgEndMs, lessThanOrEqualTo(40000));
    });

    test('silence / unknown bg is a no-op', () {
      const span = SegmentSpan(fgStartMs: 0, fgEndMs: 5000);
      expect(
        SegmentSpanMath.slideBgWindow(span, 9999, fgDurMs: 100000, bgDurMs: 0),
        span,
      );
    });

    test('an impossible alignment retreats to a feasible one', () {
      // bg 10s, fg 100s: no offset can cover the whole fg, but a minimum
      // window must always remain reachable.
      const span = SegmentSpan(fgStartMs: 40000, fgEndMs: 90000, bgOffsetMs: 0);
      final out = SegmentSpanMath.slideBgWindow(span, 100000,
          fgDurMs: 100000, bgDurMs: 10000);
      expect(out.bgStartMs, greaterThanOrEqualTo(0));
      expect(out.bgEndMs, lessThanOrEqualTo(10000));
      expect(out.lengthMs, greaterThanOrEqualTo(kMinSegmentSpanMs));
    });

    test('a bg shorter than the minimum never throws on an inverted clamp', () {
      // fg 100s, bg 100ms: NO offset leaves even the minimum window, so no
      // feasible candidate exists. The clamp domain is empty (maxB < minA) and
      // must not be fed to `clamp` (that throws ArgumentError and red-screens).
      const span = SegmentSpan(fgStartMs: 0, fgEndMs: 50, bgOffsetMs: 0);
      late SegmentSpan out;
      expect(
        () => out = SegmentSpanMath.slideBgWindow(span, 1000,
            fgDurMs: 100000, bgDurMs: 100),
        returnsNormally,
      );
      expect(out.fgStartMs, lessThanOrEqualTo(out.fgEndMs));
    });
  });

  group('SegmentSpanMath movePointTo', () {
    test('P aligns the bg cursor onto the fg cursor', () {
      const span = SegmentSpan(fgStartMs: 30000, fgEndMs: 40000, bgOffsetMs: -30000);
      final out = SegmentSpanMath.movePointTo(
        span: span,
        point: SegmentPoint.p,
        fgMs: 35000,
        bgMs: 30000,
        fgDurMs: 100000,
        bgDurMs: 40000,
        minSpanMs: kDefaultMinSegmentSpanMs,
      );
      expect(out.bgOffsetMs, -5000);
      expect(out.bgStartMs, 25000);
    });

    test('P without a bg cursor is a no-op', () {
      const span = SegmentSpan(fgStartMs: 30000, fgEndMs: 40000, bgOffsetMs: -30000);
      expect(
        SegmentSpanMath.movePointTo(
          span: span,
          point: SegmentPoint.p,
          fgMs: 35000,
          fgDurMs: 100000,
          bgDurMs: 40000,
          minSpanMs: kDefaultMinSegmentSpanMs,
        ),
        span,
      );
    });

    test('A / B moves still stop at the A<P<B gate', () {
      const span = SegmentSpan(fgStartMs: 30000, fgEndMs: 50000, bgOffsetMs: 0);
      final a = SegmentSpanMath.movePointTo(
          span: span, point: SegmentPoint.a, fgMs: 60000,
          fgDurMs: 100000, bgDurMs: 100000,
          minSpanMs: kDefaultMinSegmentSpanMs);
      expect(a, span);
      final b = SegmentSpanMath.movePointTo(
          span: span, point: SegmentPoint.b, fgMs: 10000,
          fgDurMs: 100000, bgDurMs: 100000,
          minSpanMs: kDefaultMinSegmentSpanMs);
      expect(b, span);
    });
  });

  group('SegmentSpanMath canMovePoint', () {
    test('A is movable left of the centre', () {
      expect(
        SegmentSpanMath.canMovePoint(
            point: SegmentPoint.a, fgMs: 35000, centerMs: 40000),
        isTrue,
      );
    });

    test('A is not movable at/right of the centre', () {
      expect(
        SegmentSpanMath.canMovePoint(
            point: SegmentPoint.a, fgMs: 40000, centerMs: 40000),
        isFalse,
      );
      expect(
        SegmentSpanMath.canMovePoint(
            point: SegmentPoint.a, fgMs: 45000, centerMs: 40000),
        isFalse,
      );
    });

    test('B is movable right of the centre', () {
      expect(
        SegmentSpanMath.canMovePoint(
            point: SegmentPoint.b, fgMs: 45000, centerMs: 40000),
        isTrue,
      );
    });

    test('B is not movable at/left of the centre', () {
      expect(
        SegmentSpanMath.canMovePoint(
            point: SegmentPoint.b, fgMs: 40000, centerMs: 40000),
        isFalse,
      );
      expect(
        SegmentSpanMath.canMovePoint(
            point: SegmentPoint.b, fgMs: 35000, centerMs: 40000),
        isFalse,
      );
    });

    test('P is always movable', () {
      for (final fgMs in const <int>[0, 40000, 80000]) {
        expect(
          SegmentSpanMath.canMovePoint(
              point: SegmentPoint.p, fgMs: fgMs, centerMs: 40000),
          isTrue,
        );
      }
    });
  });

  group('SegmentSpanMath fullFeasibleSpan', () {
    test('off = 0 ⇒ the whole overlap [0, min(fg, bg)]', () {
      final s = SegmentSpanMath.fullFeasibleSpan(
          fgDurMs: 100000, bgDurMs: 40000, bgOffsetMs: 0);
      expect(s.fgStartMs, 0);
      expect(s.fgEndMs, 40000);
      expect(s.bgStartMs, 0);
      expect(s.bgEndMs, 40000);
    });

    test('bg lagging 30s ⇒ A starts at the align point (30s)', () {
      final s = SegmentSpanMath.fullFeasibleSpan(
          fgDurMs: 100000, bgDurMs: 40000, bgOffsetMs: -30000);
      expect(s.fgStartMs, 30000);
      expect(s.fgEndMs, 70000);
      expect(s.bgStartMs, 0);
    });

    test('bg leading 10s ⇒ A is capped at the video head', () {
      final s = SegmentSpanMath.fullFeasibleSpan(
          fgDurMs: 100000, bgDurMs: 40000, bgOffsetMs: 10000);
      expect(s.fgStartMs, 0);
      expect(s.fgEndMs, 30000); // bg tail = bgDur − off
      expect(s.bgEndMs, 40000);
    });

    test('no bg ⇒ the span collapses to the foreground axis', () {
      final s = SegmentSpanMath.fullFeasibleSpan(
          fgDurMs: 100000, bgDurMs: 0, bgOffsetMs: 0);
      expect(s.fgStartMs, 0);
      expect(s.fgEndMs, 100000);
    });
  });

  group('SegmentSpanMath dragAlignment (P = slide, grow, or truncate)', () {
    test('slides when both ends are inside the media (length kept)', () {
      const ref = SegmentSpan(
          fgStartMs: 30000, fgEndMs: 50000, bgOffsetMs: -30000);
      final out = SegmentSpanMath.dragAlignment(ref, 5000,
          fgDurMs: 100000, bgDurMs: 40000);
      expect(out.fgStartMs, 35000);
      expect(out.fgEndMs, 55000);
      expect(out.bgOffsetMs, -35000);
      expect(out.lengthMs, 20000, reason: 'length preserved');
      expect(out.bgStartMs, 0, reason: 'bg content stays put in bg time');
      expect(out.bgEndMs, 20000);
    });

    test('a manually shortened span slides with the readouts frozen', () {
      // bg window [0, 20s] out of a 40s bg, laid over fg [20s, 40s].
      const ref =
          SegmentSpan(fgStartMs: 20000, fgEndMs: 40000, bgOffsetMs: -20000);
      final out = SegmentSpanMath.dragAlignment(ref, 30000,
          fgDurMs: 100000, bgDurMs: 40000);
      expect(out.fgStartMs, 50000, reason: 'A moved');
      expect(out.fgEndMs, 70000, reason: 'B moved by the same amount');
      expect(out.lengthMs, 20000, reason: 'length untouched');
      expect(SegmentSpanMath.leadInMs(out), 0, reason: 'A readout frozen');
      expect(SegmentSpanMath.tailMs(out, 40000), -20000,
          reason: 'B readout frozen');
    });

    test('A pinned at the head: B follows the drag with its readout frozen', () {
      // off = +5s → A's unused bg head is 5s, B's unused tail is 15s. A is
      // already at the video head, so the window cannot slide: it keeps
      // travelling, which moves B in by the full 5s. B's bg correspondence (and
      // so its `-??`) is untouched, while A's own readout grows to 10s.
      const ref =
          SegmentSpan(fgStartMs: 0, fgEndMs: 20000, bgOffsetMs: 5000);
      final out = SegmentSpanMath.dragAlignment(ref, -5000,
          fgDurMs: 100000, bgDurMs: 40000);
      expect(out.fgStartMs, 0, reason: 'A holds at the head');
      expect(out.fgEndMs, 15000, reason: 'B followed the drag');
      expect(out.lengthMs, 15000, reason: 'the window shortened at B');
      expect(out.bgOffsetMs, 10000);
      expect(SegmentSpanMath.leadInMs(out), 10000,
          reason: "A's readout grew from 5000");
      expect(SegmentSpanMath.tailMs(out, 40000), -15000,
          reason: "B's readout is frozen");
    });

    test('a long pull keeps A pinned and truncates the span at B', () {
      const ref =
          SegmentSpan(fgStartMs: 0, fgEndMs: 20000, bgOffsetMs: 5000);
      final out = SegmentSpanMath.dragAlignment(ref, -15000,
          fgDurMs: 100000, bgDurMs: 40000);
      expect(out.fgStartMs, 0, reason: 'A stays pinned at the head');
      expect(out.fgEndMs, 5000, reason: 'B took the whole gesture');
      expect(out.lengthMs, 5000, reason: 'the span shortened');
      expect(SegmentSpanMath.leadInMs(out), 20000,
          reason: "A's readout grew");
      expect(SegmentSpanMath.tailMs(out, 40000), -15000,
          reason: "B's readout is still frozen");
    });

    test('B pinned at the end: A follows the drag with its readout frozen', () {
      // bg is longer than the fg → B sits at the video end with 40s of unused
      // bg tail. Dragging toward 100% moves A out by the full 5s while B holds.
      const ref =
          SegmentSpan(fgStartMs: 45000, fgEndMs: 60000, bgOffsetMs: 0);
      final out = SegmentSpanMath.dragAlignment(ref, 5000,
          fgDurMs: 60000, bgDurMs: 100000);
      expect(out.fgStartMs, 50000, reason: 'A followed the drag');
      expect(out.fgEndMs, 60000, reason: 'B holds at the fg end');
      expect(out.lengthMs, 10000, reason: 'the window shortened at A');
      expect(out.bgOffsetMs, -5000);
      expect(SegmentSpanMath.leadInMs(out), 45000,
          reason: "A's readout is frozen");
      expect(SegmentSpanMath.tailMs(out, 100000), -45000,
          reason: "B's readout grew from -40000");
    });

    test('pins an end and truncates; the same delta restores it from the ref',
        () {
      const ref = SegmentSpan(fgStartMs: 0, fgEndMs: 20000, bgOffsetMs: 0);
      final out = SegmentSpanMath.dragAlignment(ref, 45000,
          fgDurMs: 60000, bgDurMs: 60000);
      expect(out.fgEndMs, 60000, reason: 'B is pinned at the fg end');
      expect(out.fgStartMs, 45000);
      expect(out.lengthMs, 15000, reason: 'the window truncated');

      final back = SegmentSpanMath.dragAlignment(ref, 30000,
          fgDurMs: 60000, bgDurMs: 60000);
      expect(back.fgStartMs, 30000);
      expect(back.fgEndMs, 50000);
      expect(back.lengthMs, 20000, reason: 'back inside the media → restored');
    });
  });

  group('SegmentSpanMath dragAlignment pull-away seals', () {
    test('pulling away from A at the head consumes the pile, then translates',
        () {
      // A on the table with 5s of head pile in a 40s bg over fg 0–100s.
      const ref = SegmentSpan(
          fgStartMs: 0, fgEndMs: 20000, bgOffsetMs: 5000);
      final out = SegmentSpanMath.dragAlignment(ref, 8000,
          fgDurMs: 100000, bgDurMs: 40000);
      // 5s of pile spent (A holds, B follows), then 3s translate.
      expect(out.fgStartMs, 3000);
      expect(out.fgEndMs, 28000);
      expect(out.bgOffsetMs, -3000);
      expect(out.lengthMs, 25000);
      expect(SegmentSpanMath.leadInMs(out), 0);
      expect(SegmentSpanMath.tailMs(out, 40000), -15000);
    });

    test('a sealed pile survives the pull-away', () {
      const ref = SegmentSpan(
          fgStartMs: 0, fgEndMs: 20000, bgOffsetMs: 5000);
      final out = SegmentSpanMath.dragAlignment(ref, 8000,
          fgDurMs: 100000, bgDurMs: 40000, sealLeadMs: 2000);
      // 3s of new pile spent (5s → the 2s seal), then 5s translate.
      expect(out.fgStartMs, 5000);
      expect(out.fgEndMs, 28000);
      expect(out.bgOffsetMs, -3000);
      expect(SegmentSpanMath.leadInMs(out), 2000);
    });

    test('pulling away from B at the end consumes the tail', () {
      // bg window 45–60s in a 100s bg over fg 0–60s.
      const ref =
          SegmentSpan(fgStartMs: 45000, fgEndMs: 60000, bgOffsetMs: 0);
      final out = SegmentSpanMath.dragAlignment(ref, -5000,
          fgDurMs: 60000, bgDurMs: 100000);
      expect(out.fgStartMs, 40000, reason: 'A follows the drag');
      expect(out.fgEndMs, 60000, reason: 'B stays pinned at the fg end');
      expect(out.bgOffsetMs, 5000);
      expect(SegmentSpanMath.tailMs(out, 100000), -35000);
    });

    test('a sealed tail survives, the remainder translates', () {
      const ref =
          SegmentSpan(fgStartMs: 45000, fgEndMs: 60000, bgOffsetMs: 0);
      final out = SegmentSpanMath.dragAlignment(ref, -10000,
          fgDurMs: 60000, bgDurMs: 100000, sealTailMs: 35000);
      // 5s of new tail spent (40s → the 35s seal), then 5s translate.
      expect(out.fgStartMs, 35000);
      expect(out.fgEndMs, 55000);
      expect(out.bgOffsetMs, 10000);
      expect(SegmentSpanMath.tailMs(out, 100000), -35000);
    });

    test('both ends at bounds trade piles', () {
      // A on the table and B on the wall: only the offset can move.
      const ref = SegmentSpan(
          fgStartMs: 0, fgEndMs: 60000, bgOffsetMs: 10000);
      final out = SegmentSpanMath.dragAlignment(ref, 5000,
          fgDurMs: 60000, bgDurMs: 100000);
      expect(out.fgStartMs, 0);
      expect(out.fgEndMs, 60000);
      expect(out.bgOffsetMs, 5000);
      expect(SegmentSpanMath.leadInMs(out), 5000);
      expect(SegmentSpanMath.tailMs(out, 100000), -35000);
    });
  });

  group('SegmentSpanMath dragAlignment keepMaxLength = false', () {
    test('ignores the seal and consumes the pile to 0', () {
      const ref = SegmentSpan(
          fgStartMs: 0, fgEndMs: 20000, bgOffsetMs: 5000);
      final out = SegmentSpanMath.dragAlignment(ref, 8000,
          fgDurMs: 100000, bgDurMs: 40000,
          keepMaxLength: false, sealLeadMs: 2000);
      expect(out.fgStartMs, 3000);
      expect(out.fgEndMs, 28000);
      expect(out.bgOffsetMs, -3000);
      expect(SegmentSpanMath.leadInMs(out), 0);
    });

    test('an interior window still translates normally', () {
      const ref =
          SegmentSpan(fgStartMs: 30000, fgEndMs: 50000, bgOffsetMs: -30000);
      final out = SegmentSpanMath.dragAlignment(ref, 5000,
          fgDurMs: 100000, bgDurMs: 40000, keepMaxLength: false);
      expect(out.fgStartMs, 35000);
      expect(out.fgEndMs, 55000);
      expect(out.lengthMs, 20000);
    });
  });

  group('SegmentSpanMath sealsFor', () {
    test('boundary ends unseal, interior ends keep the current pile', () {
      const span = SegmentSpan(
          fgStartMs: 0, fgEndMs: 20000, bgOffsetMs: 5000);
      final s =
          SegmentSpanMath.sealsFor(span, fgDurMs: 100000, bgDurMs: 40000);
      expect(s.lead, 0, reason: 'A on the table is unsealed');
      expect(s.tail, 15000, reason: 'B in the air keeps its pile');
    });

    test('interior ends keep both piles', () {
      const span = SegmentSpan(
          fgStartMs: 30000, fgEndMs: 50000, bgOffsetMs: -20000);
      final s =
          SegmentSpanMath.sealsFor(span, fgDurMs: 100000, bgDurMs: 40000);
      expect(s.lead, 10000);
      expect(s.tail, 10000);
    });

    test('an end on the wall unseals', () {
      const span =
          SegmentSpan(fgStartMs: 45000, fgEndMs: 60000, bgOffsetMs: 0);
      final s =
          SegmentSpanMath.sealsFor(span, fgDurMs: 60000, bgDurMs: 100000);
      expect(s.lead, 45000, reason: 'A in the air keeps its pile');
      expect(s.tail, 0, reason: 'B on the wall is unsealed');
    });
  });

  group('BgStickyConsume', () {
    test('pSticky / abSticky reflect the four tiers', () {
      expect(BgStickyConsume.off.pSticky, isFalse);
      expect(BgStickyConsume.off.abSticky, isFalse);
      expect(BgStickyConsume.pOnly.pSticky, isTrue);
      expect(BgStickyConsume.pOnly.abSticky, isFalse);
      expect(BgStickyConsume.abOnly.pSticky, isFalse);
      expect(BgStickyConsume.abOnly.abSticky, isTrue);
      expect(BgStickyConsume.all.pSticky, isTrue);
      expect(BgStickyConsume.all.abSticky, isTrue);
    });
  });

  group('SegmentSpanMath sticky consumption', () {
    test('P pull-away with pSticky false translates and freezes the pile', () {
      const ref = SegmentSpan(fgStartMs: 0, fgEndMs: 20000, bgOffsetMs: 5000);
      final out = SegmentSpanMath.dragAlignment(ref, 8000,
          fgDurMs: 100000, bgDurMs: 40000, pSticky: false);
      expect(out.fgStartMs, 8000, reason: 'A left the head');
      expect(out.fgEndMs, 28000);
      expect(out.bgOffsetMs, -3000);
      expect(out.lengthMs, 20000, reason: 'length preserved');
      expect(SegmentSpanMath.leadInMs(out), 5000, reason: 'pile frozen');
    });

    test('B outward without sticky translates, leaving the opposite end', () {
      // A on the head with a 10s lead pile; B has no tail left.
      const span = SegmentSpan(fgStartMs: 0, fgEndMs: 30000, bgOffsetMs: 10000);
      final out = SegmentSpanMath.dragEnd(span, 40000,
          fgDurMs: 100000, bgDurMs: 40000, minSpanMs: kDefaultMinSegmentSpanMs);
      expect(out.fgStartMs, 10000, reason: 'A left the head');
      expect(out.fgEndMs, 40000);
      expect(out.bgOffsetMs, 0);
      expect(SegmentSpanMath.leadInMs(out), 10000, reason: 'lead untouched');
    });

    test('B outward sticky spends the opposite lead once its own tail is gone',
        () {
      const span = SegmentSpan(fgStartMs: 0, fgEndMs: 30000, bgOffsetMs: 10000);
      final out = SegmentSpanMath.dragEnd(span, 40000,
          fgDurMs: 100000,
          bgDurMs: 40000,
          minSpanMs: kDefaultMinSegmentSpanMs,
          sticky: true);
      expect(out.fgStartMs, 0, reason: 'A holds at the head');
      expect(out.fgEndMs, 40000, reason: 'B took the whole gesture');
      expect(out.bgOffsetMs, 0);
      expect(SegmentSpanMath.leadInMs(out), 0, reason: 'lead consumed');
    });

    test('a sealed opposite lead survives a B-outward drag', () {
      const span = SegmentSpan(fgStartMs: 0, fgEndMs: 30000, bgOffsetMs: 10000);
      final out = SegmentSpanMath.dragEnd(span, 40000,
          fgDurMs: 100000,
          bgDurMs: 40000,
          minSpanMs: kDefaultMinSegmentSpanMs,
          sticky: true,
          sealLeadMs: 4000);
      expect(out.fgStartMs, 4000, reason: 'the remainder translated');
      expect(out.fgEndMs, 40000);
      expect(out.bgOffsetMs, 0);
      expect(SegmentSpanMath.leadInMs(out), 4000, reason: 'seal survives');
    });

    test('keepMaxLength = false lets the opposite lead reach zero', () {
      const span = SegmentSpan(fgStartMs: 0, fgEndMs: 30000, bgOffsetMs: 10000);
      final out = SegmentSpanMath.dragEnd(span, 40000,
          fgDurMs: 100000,
          bgDurMs: 40000,
          minSpanMs: kDefaultMinSegmentSpanMs,
          sticky: true,
          keepMaxLength: false,
          sealLeadMs: 4000);
      expect(out.fgStartMs, 0);
      expect(out.fgEndMs, 40000);
      expect(SegmentSpanMath.leadInMs(out), 0);
    });

    test('A outward sticky spends the opposite tail once its own lead is gone',
        () {
      // A lead already 0 (bg head aligned at A); B on the fg end with a 5s tail.
      const span =
          SegmentSpan(fgStartMs: 65000, fgEndMs: 100000, bgOffsetMs: -65000);
      final out = SegmentSpanMath.dragStart(span, 55000,
          fgDurMs: 100000,
          bgDurMs: 40000,
          minSpanMs: kDefaultMinSegmentSpanMs,
          sticky: true);
      expect(out.fgStartMs, 55000, reason: 'A took the whole gesture');
      expect(out.fgEndMs, 95000, reason: 'B held, then the remainder moved');
      expect(out.bgOffsetMs, -55000);
      expect(out.bgStartMs, 0, reason: 'lead stays exhausted');
      expect(SegmentSpanMath.tailMs(out, 40000), 0, reason: 'tail consumed');
    });

    test('a sealed opposite tail survives an A-outward drag', () {
      const span =
          SegmentSpan(fgStartMs: 65000, fgEndMs: 100000, bgOffsetMs: -65000);
      final out = SegmentSpanMath.dragStart(span, 55000,
          fgDurMs: 100000,
          bgDurMs: 40000,
          minSpanMs: kDefaultMinSegmentSpanMs,
          sticky: true,
          sealTailMs: 2000);
      expect(out.fgStartMs, 55000);
      expect(SegmentSpanMath.tailMs(out, 40000), -2000,
          reason: '2s of unused tail (the seal) survives');
    });

    test('sticky spends own tail before touching the opposite lead', () {
      const span =
          SegmentSpan(fgStartMs: 10000, fgEndMs: 30000, bgOffsetMs: -10000);
      final out = SegmentSpanMath.dragEnd(span, 40000,
          fgDurMs: 100000,
          bgDurMs: 40000,
          minSpanMs: kDefaultMinSegmentSpanMs,
          sticky: true);
      expect(out.fgEndMs, 40000);
      expect(out.fgStartMs, 10000, reason: 'A stays while own tail is spent');
      expect(out.bgOffsetMs, -10000);
    });
  });

  group('SegmentSpanMath readouts', () {
    test('lead-in is the bg time skipped before A', () {
      const span = SegmentSpan(fgStartMs: 0, fgEndMs: 30000, bgOffsetMs: 30000);
      expect(SegmentSpanMath.leadInMs(span), 30000);
    });

    test('tail is the bg overflow past B, negative when unused', () {
      const overflow = SegmentSpan(fgStartMs: 0, fgEndMs: 60000, bgOffsetMs: -30000);
      expect(SegmentSpanMath.tailMs(overflow, 40000), -10000);
      const past = SegmentSpan(fgStartMs: 0, fgEndMs: 50000, bgOffsetMs: 0);
      expect(SegmentSpanMath.tailMs(past, 40000), 10000);
      expect(SegmentSpanMath.tailMs(past, 0), 0);
    });

    test('earliest alignment point is the fg position of bg 00:00', () {
      expect(SegmentSpanMath.earliestAlignFgMs(
          const SegmentSpan(fgStartMs: 0, fgEndMs: 1, bgOffsetMs: 30000)), -30000);
      expect(SegmentSpanMath.earliestAlignFgMs(
          const SegmentSpan(fgStartMs: 0, fgEndMs: 1, bgOffsetMs: -30000)), 30000);
    });
  });
}

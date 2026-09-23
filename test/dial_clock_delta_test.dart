import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/background_playback/resolver/segment_span_math.dart';
import 'package:iris/features/background_playback/view/segment_dual_ring_dial.dart';

/// The dual-ring dial drags RELATIVE to the touch-down angle, so it must step
/// the shortest way around the circle — otherwise crossing the 11→12 notch
/// would read as a −330° jump and the A/B/P window would snap to the far end
/// (the reported "跳成长孤/短孤").
void main() {
  group('shortestClockDelta', () {
    test('small forward / backward steps pass through unchanged', () {
      expect(shortestClockDelta(10, 15), 5);
      expect(shortestClockDelta(15, 10), -5);
    });

    test('crossing the notch the short way is a small step, not a -330 jump',
        () {
      // 350° → 5° is +15° through 0°, never -345°.
      expect(shortestClockDelta(350, 5), 15);
      // And the reverse is -15°.
      expect(shortestClockDelta(5, 350), -15);
    });

    test('the half-turn boundary is a full +180 (not -180)', () {
      expect(shortestClockDelta(0, 180), 180);
      expect(shortestClockDelta(0, 181), -179);
    });

    test('identical angles are a no-op', () {
      expect(shortestClockDelta(123, 123), 0);
    });

    test('the A/P/B bands are radial, distinct, inward, and non-overlapping',
        () {
      const bgR = 80.0;
      final a = handleRadiusFor(SegmentPoint.a, bgR);
      final p = handleRadiusFor(SegmentPoint.p, bgR);
      final b = handleRadiusFor(SegmentPoint.b, bgR);
      expect(a, bgR);
      expect(p, lessThan(a));
      expect(b, lessThan(p));
      // No two hit bands may overlap, else a touch could resolve to two.
      expect(kDialHandleRadialStep, greaterThan(2 * kDialHandleRadialTol));
    });

    test('accumulating across several notch crossings stays bounded', () {
      // Simulate a finger sweeping 350 → 5 → 20 → 340.
      var total = 0.0;
      var last = 350.0;
      for (final next in [5.0, 20.0, 340.0]) {
        total += shortestClockDelta(last, next);
        last = next;
      }
      // 350→5 (+15), 5→20 (+15), 20→340 (-40).
      expect(total, -10);
    });
  });
}

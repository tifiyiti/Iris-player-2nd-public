import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/speed/model/speed_rate_scale_math.dart';
import 'package:iris/globals.dart' show speedStops;

/// Piecewise-linear track mapping contract.
///
/// A flat 0.1..10.0 axis would squeeze 0.1..1.0 into the leftmost 9% of the
/// slider (unreachable with a thumb) while handing 9.0..10.0 a tenth of the
/// travel (useless), so the track is split into three hand-tuned segments:
/// slow gets most of it, normal a solid share, and the long tail the rest.
void main() {
  test('segment anchors land on their documented fractions', () {
    expect(rateToFraction(0.1), closeTo(0.0, 1e-9), reason: 'track start');
    expect(rateToFraction(1.0), closeTo(0.45, 1e-9), reason: 'slow segment');
    expect(rateToFraction(2.0), closeTo(0.75, 1e-9), reason: 'normal segment');
    expect(rateToFraction(10.0), closeTo(1.0, 1e-9), reason: 'track end');
  });

  test('every speed stop maps strictly left-to-right', () {
    double previous = -1.0;
    for (final double rate in speedStops) {
      final double fraction = rateToFraction(rate);
      expect(fraction, inInclusiveRange(0.0, 1.0));
      expect(fraction, greaterThan(previous),
          reason: '$rate must sit right of the stop before it');
      previous = fraction;
    }
  });

  test('round-trips every one of the 100 speed stops', () {
    for (final double rate in speedStops) {
      expect(fractionToRate(rateToFraction(rate)), closeTo(rate, 1e-9),
          reason: '$rate must survive a there-and-back trip unrounded');
    }
  });

  test('the slow and normal ranges keep most of the travel', () {
    // Linear would give 0.1..1.0 only 9%. These floors are the whole point
    // of the segmentation: without them the slider regresses to a linear one.
    expect(rateToFraction(1.0) - rateToFraction(0.1), greaterThan(0.40),
        reason: '0.1..1.0 must own at least 40% of the track');
    expect(rateToFraction(2.0) - rateToFraction(1.0), greaterThan(0.25),
        reason: '1.0..2.0 must own at least 25%');
    expect(rateToFraction(10.0) - rateToFraction(2.0), lessThan(0.30),
        reason: 'the 2..10 tail is the least-tapped range, so it gets least');
  });

  test('fractionToRate snaps onto the shared 0.1 grid', () {
    expect(fractionToRate(0.0), kRateMin, reason: 'left end is the floor');
    expect(fractionToRate(1.0), kRateMax, reason: 'right end is the ceiling');
    for (final double t in const <double>[0.0, 0.1, 0.23, 0.5, 0.66, 0.9, 1.0]) {
      final double rate = fractionToRate(t);
      expect(rate, inInclusiveRange(kRateMin, kRateMax));
      expect((rate * 10).roundToDouble(), closeTo(rate * 10, 1e-9),
          reason: 't=$t landed off the 0.1 grid the wheels/list share');
    }
  });

  test('rateScaleTicks exposes exactly the label anchors', () {
    final List<({double fraction, double rate})> ticks = rateScaleTicks();
    expect(ticks.map((tick) => tick.rate).toList(),
        <double>[kRateMin, kRateScaleSlowEnd, kRateScaleNormalEnd, kRateMax],
        reason: 'tick labels sit on segment boundaries only');
    expect(ticks.first.fraction, closeTo(0.0, 1e-9));
    expect(ticks.last.fraction, closeTo(1.0, 1e-9));
  });

  test('the label formatter keeps industry chip values intact', () {
    // Chips offer the usual 0.25-based set, which the 0.1 grid cannot hold;
    // the formatter must not flatten 0.25 into "0.3".
    expect(formatSpeedLabel(1.0), '1.0');
    expect(formatSpeedLabel(0.25), '0.25');
    expect(formatSpeedLabel(0.75), '0.75');
    expect(formatSpeedLabel(1.25), '1.25');
    expect(formatSpeedLabel(1.5), '1.5');
    expect(formatSpeedLabel(3.7), '3.7');
    expect(formatSpeedLabel(10.0), '10.0');
    expect(formatSpeedLabel(kRateMin), '0.1');
  });

  group('horizontal drag', () {
    test('a full track width spans the whole range', () {
      // The drag surface and the control-bar button-to-be share this rule, so
      // pin the endpoints: dragging right raises, dragging left lowers, and one
      // track width covers the lot.
      expect(rateAfterHorizontalDrag(kRateMin, kRateDragTrackWidth), kRateMax);
      expect(
        rateAfterHorizontalDrag(kRateMax, -kRateDragTrackWidth),
        kRateMin,
      );
    });

    test('moves in fraction space, not rate space', () {
      // 100px near the compressed 2..10 tail must move the rate by MORE than
      // the same 100px in the dense 0.1..1.0 head — a linear rate-per-pixel
      // step would make the tail crawl.
      final double head = rateAfterHorizontalDrag(0.5, 100) - 0.5;
      final double tail = rateAfterHorizontalDrag(5.0, 100) - 5.0;
      expect(tail, greaterThan(head));
    });

    test('is clamped to the playable range', () {
      expect(rateAfterHorizontalDrag(kRateMax, 9999), kRateMax);
      expect(rateAfterHorizontalDrag(kRateMin, -9999), kRateMin);
    });

    test('always lands on the shared 0.1 grid', () {
      for (final double dx in const <double>[-137, -12, 0, 9, 63, 240]) {
        final double rate = rateAfterHorizontalDrag(1.5, dx);
        expect((rate * 10).roundToDouble(), closeTo(rate * 10, 1e-9),
            reason: 'dx=$dx landed off the grid the wheels/list share');
      }
    });
  });
}

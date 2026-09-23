import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/background_playback/resolver/segment_span_math.dart';

/// The "move A/P/B to the current position" buttons must respect A < P < B:
/// the playhead's side (AP vs PB) decides which two points are movable, and a
/// move can never invert the order. P sets the ALIGNMENT (bg cursor onto fg
/// cursor) and re-clamps A/B into the range where bg content exists.
void main() {
  // A=10s, B=30s → P=20s.
  const span = SegmentSpan(
    fgStartMs: 10000,
    fgEndMs: 30000,
    bgOffsetMs: 0,
  );

  group('movablePointsFor', () {
    test('playhead on the A-P side ⇒ A and P movable, B not', () {
      final m = SegmentSpanMath.movablePointsFor(span: span, fgMs: 15000);
      expect(m.a, isTrue);
      expect(m.p, isTrue);
      expect(m.b, isFalse);
    });

    test('playhead on the P-B side ⇒ B and P movable, A not', () {
      final m = SegmentSpanMath.movablePointsFor(span: span, fgMs: 25000);
      expect(m.a, isFalse);
      expect(m.p, isTrue);
      expect(m.b, isTrue);
    });

    test('exactly at P ⇒ neither side (only P)', () {
      final m = SegmentSpanMath.movablePointsFor(span: span, fgMs: 20000);
      expect(m.a, isFalse);
      expect(m.p, isTrue);
      expect(m.b, isFalse);
    });
  });

  group('movePointTo', () {
    test('A snaps to the playhead when it is left of P', () {
      final next = SegmentSpanMath.movePointTo(
        span: span,
        point: SegmentPoint.a,
        fgMs: 12000,
        fgDurMs: 60000,
        bgDurMs: 60000,
        minSpanMs: kDefaultMinSegmentSpanMs,
      );
      expect(next.fgStartMs, 12000);
      expect(next.fgEndMs, 30000, reason: 'B is untouched');
    });

    test('A refuses to cross P', () {
      final next = SegmentSpanMath.movePointTo(
        span: span,
        point: SegmentPoint.a,
        fgMs: 25000,
        fgDurMs: 60000,
        bgDurMs: 60000,
        minSpanMs: kDefaultMinSegmentSpanMs,
      );
      expect(next, span);
    });

    test('B snaps to the playhead when it is right of P', () {
      final next = SegmentSpanMath.movePointTo(
        span: span,
        point: SegmentPoint.b,
        fgMs: 28000,
        fgDurMs: 60000,
        bgDurMs: 60000,
        minSpanMs: kDefaultMinSegmentSpanMs,
      );
      expect(next.fgEndMs, 28000);
      expect(next.fgStartMs, 10000, reason: 'A is untouched');
    });

    test('B refuses to cross A/P', () {
      final next = SegmentSpanMath.movePointTo(
        span: span,
        point: SegmentPoint.b,
        fgMs: 15000,
        fgDurMs: 60000,
        bgDurMs: 60000,
        minSpanMs: kDefaultMinSegmentSpanMs,
      );
      expect(next, span);
    });

    test('P aligns the bg cursor onto the fg cursor', () {
      final next = SegmentSpanMath.movePointTo(
        span: span,
        point: SegmentPoint.p,
        fgMs: 25000,
        bgMs: 20000,
        fgDurMs: 60000,
        bgDurMs: 60000,
        minSpanMs: kDefaultMinSegmentSpanMs,
      );
      expect(next.bgOffsetMs, -5000);
      expect(next.bgStartMs, 5000);
    });

    test('P re-clamps the usable range when the alignment shrinks it', () {
      final next = SegmentSpanMath.movePointTo(
        span: span,
        point: SegmentPoint.p,
        fgMs: 0,
        bgMs: 30000, // off = +30s → bg starts 30s after A
        fgDurMs: 60000,
        bgDurMs: 60000,
        minSpanMs: kDefaultMinSegmentSpanMs,
      );
      expect(next.bgOffsetMs, 30000);
      expect(next.bgStartMs, greaterThanOrEqualTo(0));
      expect(next.fgEndMs, lessThanOrEqualTo(30000));
    });

    test('movePointTo respects the bg duration bound', () {
      // bg only 5s long → B cannot exceed 5s (1:1 offset 0).
      final next = SegmentSpanMath.movePointTo(
        span: span,
        point: SegmentPoint.b,
        fgMs: 28000,
        fgDurMs: 60000,
        bgDurMs: 5000,
        minSpanMs: kDefaultMinSegmentSpanMs,
      );
      expect(next.fgEndMs, lessThanOrEqualTo(5000));
    });
  });
}

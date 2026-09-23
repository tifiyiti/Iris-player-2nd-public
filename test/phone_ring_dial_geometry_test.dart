import 'dart:ui' show Offset, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/phone/one_handed_scrubber/controller/phone_ring_dial_math.dart';

void main() {
  group('dialBox (height drives ring size, width caps it)', () {
    test('defaults reproduce the legacy fitted size exactly', () {
      final b = PhoneRingDialMath.dialBox(panelWidth: 240, maxHeight: 210);
      expect(b.width, 240);
      expect(b.height, 210);
      expect(b.diameter, 210);
    });

    test('box width equals the panel width — no separate width share', () {
      expect(
        PhoneRingDialMath.dialBox(panelWidth: 500, maxHeight: 210).width,
        500,
        reason: 'the dial canvas inherits the legacy panel width as-is',
      );
    });

    test('diameter follows HEIGHT, but never past the panel width', () {
      final b = PhoneRingDialMath.dialBox(panelWidth: 240, maxHeight: 400);
      expect(b.diameter, 240,
          reason: 'a ring wider than its panel could not be displayed at all');
      expect(b.width, 240);
      expect(b.height, 400,
          reason: 'the box keeps the height budget so the ring stays centred');
      expect(
        PhoneRingDialMath.dialBox(panelWidth: 500, maxHeight: 210).diameter,
        210,
        reason: 'a wide panel still lets height drive the ring',
      );
    });

    test('ring is never wider than its panel across the size matrix', () {
      for (final double w in <double>[120, 180, 200, 240, 360]) {
        for (final double h in <double>[100, 240, 400, 900]) {
          final b = PhoneRingDialMath.dialBox(panelWidth: w, maxHeight: h);
          expect(b.diameter, lessThanOrEqualTo(w + 1e-9),
              reason: 'w=$w h=$h');
        }
      }
    });

    test('height share shrinks the circle itself', () {
      final b = PhoneRingDialMath.dialBox(
        panelWidth: 500,
        maxHeight: 300,
        heightPct: 0.50,
      );
      expect(b.width, 500);
      expect(b.height, closeTo(150, 1e-9));
      expect(b.diameter, closeTo(150, 1e-9));
    });

    test('no legacy 250 px ceiling — big panels grow past it at 100%', () {
      expect(
        PhoneRingDialMath.dialBox(panelWidth: 340, maxHeight: 280).diameter,
        280,
      );
    });

    test('diameter keeps an absolute floor on cramped boxes', () {
      final b = PhoneRingDialMath.dialBox(
        panelWidth: 180,
        maxHeight: 140,
        heightPct: 0.5,
      );
      expect(b.diameter, PhoneRingDialMath.kMinDiameter);
      expect(b.height, PhoneRingDialMath.kMinDiameter,
          reason: 'box always hosts the floored circle');
    });
  });

  group('counter-clockwise notch rotation', () {
    test('level arcs: start = 12h − level·30°, sweep fixed 330°', () {
      expect(PhoneRingDialMath.arcStartClockForLevel(0), 0);
      // Inner wayfinding ring is pinned to 11→12 (0°) for UX parity.
      expect(PhoneRingDialMath.arcStartClockForLevel(1), 0);
      expect(PhoneRingDialMath.arcStartClockForLevel(2), 300);
      expect(PhoneRingDialMath.kRingLevelSweepDeg, 330);
    });

    test('inner fraction maps 12 o\'clock → 11 o\'clock clockwise', () {
      // Arc starts AT 12 o'clock (0°) — gap is 11→12 (330→360).
      expect(PhoneRingDialMath.fractionForInnerClock(0).fraction, closeTo(0, 1e-9));
      expect(PhoneRingDialMath.fractionForInnerClock(0).inGap, isFalse);
      // Just before the far edge (11 o'clock = 330°) ≈ fraction 1.
      expect(PhoneRingDialMath.fractionForInnerClock(329.9).fraction,
          closeTo(329.9 / 330, 1e-6));
      // The dead wedge 11→12 o'clock is reported as gap.
      expect(PhoneRingDialMath.fractionForInnerClock(345).inGap, isTrue);
      expect(PhoneRingDialMath.fractionForInnerClock(350).inGap, isTrue);
      // 10 o'clock sits inside the inner arc.
      expect(PhoneRingDialMath.fractionForInnerClock(300).inGap, isFalse);
    });

    test('inner drag maps the 330° sweep onto the WHOLE duration', () {
      const dur = Duration(minutes: 10);
      expect(
        PhoneRingDialMath.positionForInnerDragClock(0, dur),
        Duration.zero,
      );
      // Mid-arc angle: 0 + 165 = 165°.
      expect(
        PhoneRingDialMath.positionForInnerDragClock(165, dur)
            .closeTo(const Duration(minutes: 5), const Duration(seconds: 1)),
        isTrue,
      );
      expect(
        PhoneRingDialMath.positionForInnerDragClock(329.9, dur).inMilliseconds,
        lessThan(dur.inMilliseconds),
      );
    });

    test('inner drag inside the gap returns the previous edge value',
        () {
      const dur = Duration(minutes: 10);
      // Gap taps resolve to the wrapped end (fraction clamps to ~full sweep).
      final t = PhoneRingDialMath.positionForInnerDragClock(345, dur);
      expect(t.closeTo(dur, const Duration(milliseconds: 1200)), isTrue);
    });
  });

  group('dialGeometry', () {
    final g = PhoneRingDialMath.dialGeometry(size: const Size(210, 210));

    test('legacy parity at reference diameter', () {
      expect(g.outerR, closeTo(101, 0.05));
      expect(g.innerR, closeTo(79.5, 0.05));
      expect(g.rIn, closeTo(76, 0.05));
    });

    test('corner hit radius keeps the 22px ideal on roomy panels', () {
      expect(g.cornerHitR, 22);
    });

    test('moderate outer shrink keeps inner radius untouched', () {
      final scaled = PhoneRingDialMath.dialGeometry(
        size: const Size(210, 210),
        outerRadiusFactor: 0.95,
      );
      expect(scaled.outerR, closeTo(101 * 0.95, 0.05));
      expect(scaled.innerR, closeTo(79.5, 0.05));
    });

    test('deep outer shrink pulls inner inward before bands touch', () {
      final scaled = PhoneRingDialMath.dialGeometry(
        size: const Size(210, 210),
        outerRadiusFactor: 0.9,
      );
      expect(scaled.outerR, closeTo(101 * 0.9, 0.05));
      expect(scaled.innerR, closeTo(scaled.outerR - 13.5, 0.05));
    });

    test('inner factor beyond the collision bound is clamped (bands never touch)',
        () {
      final clamped = PhoneRingDialMath.dialGeometry(
        size: const Size(210, 210),
        innerRadiusFactor: 0.99,
      );
      expect(clamped.innerR, lessThanOrEqualTo(g.outerR - 13.5 + 0.01));
    });

    test('corner hit circles never overlap and never exceed neighbour half-distance',
        () {
      for (final double side in <double>[150, 160, 180, 210, 250]) {
        final gg = PhoneRingDialMath.dialGeometry(size: Size(side, side));
        final double nd = (gg.cornerCenters[0] - gg.cornerCenters[1]).distance;
        expect(gg.cornerHitR, lessThanOrEqualTo(nd / 2 + 1e-6),
            reason: 'side $side');
        for (int i = 0; i < 4; i++) {
          for (int j = i + 1; j < 4; j++) {
            final double d =
                (gg.cornerCenters[i] - gg.cornerCenters[j]).distance;
            expect(d, greaterThanOrEqualTo(2 * gg.cornerHitR - 1e-6),
                reason: 'side $side corners $i-$j');
          }
        }
      }
    });

    test('touch floor survives dial shrinking (hit radius never shrinks)', () {
      final small = PhoneRingDialMath.dialGeometry(size: const Size(126, 126));
      // Usable radius = side/2 − inset (inset is absolute, not proportional).
      expect(small.outerR, closeTo(126 / 2 - 4, 0.05));
      expect(small.cornerHitR, 22);
    });

    test('corner centers stay symmetric around the panel center', () {
      final Offset ctr = Offset(105, 105);
      for (int q = 0; q < 4; q++) {
        final int mirror = q ^ 3; // TL<->BR, TR<->BL
        expect((ctr - g.cornerCenters[q]).distance,
            closeTo((ctr - g.cornerCenters[mirror]).distance, 1e-6));
      }
    });
  });

  group('ring-dial setting clamps (store-layer contracts)', () {
    test('height share bounds [0.30, 1.00] — shrink-only by design', () {
      expect(clampRingDialPct(0.1), 0.30);
      expect(clampRingDialPct(1.4), 1.0);
      expect(clampRingDialPct(0.75), 0.75);
    });

    test('corridor slot ratios bound [0, 1]', () {
      expect(clampSlotT(-0.3), 0);
      expect(clampSlotT(1.7), 1);
      expect(clampSlotT(0.42), 0.42);
    });

    test('outer radius bounds', () {
      expect(clampRingDialOuterRadius(0.1), 0.80);
      expect(clampRingDialOuterRadius(1.7), 1.0);
      expect(clampRingDialOuterRadius(0.95), 0.95);
    });

    test('inner radius is bounded by the current outer radius', () {
      expect(clampRingDialInnerRadius(0.99, outerFactor: 1.0),
          clampRingDialInnerRadiusBound(outerFactor: 1.0));
      expect(clampRingDialInnerRadius(-1, outerFactor: 0.8), 0.30);
      expect(clampRingDialInnerRadius(0.85, outerFactor: 1.0), 0.81);
    });
  });
}

extension on Duration {
  bool closeTo(Duration other, Duration delta) =>
      (this - other).abs() <= delta;
}

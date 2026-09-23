import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/phone/one_handed_scrubber/controller/phone_ring_dial_math.dart';
import 'package:iris/models/store/app_state.dart';

/// Corridor placement contract for the ring (axis strip removed).
void main() {
  group('clampSlotT', () {
    test('clamps into [0,1]', () {
      expect(clampSlotT(-0.5), 0.0);
      expect(clampSlotT(0.25), 0.25);
      expect(clampSlotT(1.5), 1.0);
    });
  });

  const double w = 300;
  final RingDialBox box = PhoneRingDialMath.dialBox(
    panelWidth: w,
    maxHeight: 210,
    heightPct: 1.0,
  );

  double place({
    DialSide side = DialSide.inner,
    bool leftHanded = false,
    double ringT = 0.85,
  }) =>
      PhoneRingDialMath.dialPlacementPx(
        box: box,
        leftHanded: leftHanded,
        side: side,
        ringSlotT: ringT,
      );

  group('right-handed inner placement', () {
    test('ring fully inside the canvas', () {
      final double ringLeft = place();
      expect(ringLeft, greaterThanOrEqualTo(-0.01));
      expect(ringLeft + box.diameter, lessThanOrEqualTo(w + 0.01));
    });

    test('ring slot T sweeps from inner edge to the outer boundary', () {
      final double p0 = place(ringT: 0);
      final double p1 = place(ringT: 1);
      expect(p1, greaterThan(p0));
      expect(p1 + box.diameter, closeTo(w, 0.6));
      expect(p0, greaterThanOrEqualTo(0));
    });
  });

  group('outer placement mirrors the anchor edge', () {
    test('outer is the exact mirror of inner', () {
      final double pi = place(side: DialSide.inner, ringT: 0.7);
      final double po = place(side: DialSide.outer, ringT: 0.7);
      expect(po, closeTo(w - box.diameter - pi, 0.6));
    });
  });

  group('left-handed rendering mirrors literal coordinates', () {
    test('LH inner equals mirrored RH inner', () {
      final double pr = place(leftHanded: false);
      final double pl = place(leftHanded: true);
      expect(pl, closeTo(w - box.diameter - pr, 0.6));
    });

    test('LH outer equals RH inner (double mirror cancels)', () {
      final double pr = place(leftHanded: false, side: DialSide.inner);
      final double plo = place(leftHanded: true, side: DialSide.outer);
      expect((pr - plo).abs() < 0.6, isTrue);
    });
  });

  group('narrow canvas', () {
    test('ring is capped to the canvas width and never spills', () {
      final RingDialBox narrow = PhoneRingDialMath.dialBox(
        panelWidth: 120,
        maxHeight: 210,
        heightPct: 1.0,
      );
      expect(narrow.diameter, lessThanOrEqualTo(narrow.width + 0.01),
          reason: 'the ring must fit the canvas it is placed in');
      final double ringLeft = PhoneRingDialMath.dialPlacementPx(
        box: narrow,
        leftHanded: false,
        side: DialSide.inner,
        ringSlotT: 0.9,
      );
      expect(ringLeft, greaterThanOrEqualTo(-0.01));
      expect(ringLeft + narrow.diameter, lessThanOrEqualTo(narrow.width + 0.01));
    });
  });
}

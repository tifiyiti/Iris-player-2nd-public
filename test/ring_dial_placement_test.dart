import 'package:flutter/widgets.dart' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/phone/one_handed_scrubber/controller/phone_ring_dial_math.dart';
import 'package:iris/models/store/app_state.dart' show DialSide;

/// `ringDialPlacement` is the ONE ring placement both the normal one-handed
/// scrubber and the APB align editor use, so replacing the control bar never
/// moves or resizes the ring.
void main() {
  test('reproduces the scrubber formula for the same inputs', () {
    const double panelW = 300;
    const double maxH = 420;
    final RingDialPlacement pl = ringDialPlacement(
      panelWidth: panelW,
      maxHeight: maxH,
      heightPct: 0.9,
      outerRadiusFactor: 0.95,
      innerRadiusFactor: 0.7,
      ringSlotT: 0.3,
      side: DialSide.inner,
      leftHanded: false,
    );
    final RingDialBox box = PhoneRingDialMath.dialBox(
      panelWidth: panelW,
      maxHeight: maxH,
      heightPct: 0.9,
    );
    expect(pl.box.width, box.width);
    expect(pl.box.height, box.height);
    expect(pl.box.diameter, box.diameter);
    expect(
      pl.ringX,
      PhoneRingDialMath.dialPlacementPx(
        box: box,
        leftHanded: false,
        side: DialSide.inner,
        ringSlotT: 0.3,
      ),
    );
    expect(
      pl.geometry.outerR,
      PhoneRingDialMath.dialGeometry(
        size: Size.square(box.diameter),
        outerRadiusFactor: 0.95,
        innerRadiusFactor: 0.7,
      ).outerR,
    );
  });

  test('the sticky dialHeightPx wins over the height share', () {
    final RingDialPlacement pl = ringDialPlacement(
      panelWidth: 300,
      maxHeight: 420,
      dialHeightPx: 200,
      heightPct: 0.4,
    );
    final RingDialBox box = PhoneRingDialMath.dialBox(
      panelWidth: 300,
      maxHeight: 200,
      heightPct: 1.0,
    );
    expect(pl.box.diameter, box.diameter);
  });

  test('the ring centre stays inside the box and is input-deterministic', () {
    final RingDialPlacement a = ringDialPlacement(
      panelWidth: 320,
      maxHeight: 400,
      ringSlotT: 0.7,
      side: DialSide.outer,
      leftHanded: true,
    );
    final RingDialPlacement b = ringDialPlacement(
      panelWidth: 320,
      maxHeight: 400,
      ringSlotT: 0.7,
      side: DialSide.outer,
      leftHanded: true,
    );
    expect(a.ringCenter, b.ringCenter);
    expect(a.ringCenter.dx, a.ringX + a.box.diameter / 2);
    expect(a.ringCenter.dy, a.box.height / 2);
    // Mirrored side + left-handed keeps the ring inside the box.
    expect(a.ringX, greaterThanOrEqualTo(0));
    expect(a.ringX + a.box.diameter, lessThanOrEqualTo(a.box.width + 0.001));
  });
}

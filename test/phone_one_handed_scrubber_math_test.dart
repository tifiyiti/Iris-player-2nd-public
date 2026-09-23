import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/phone/one_handed_scrubber/controller/phone_one_handed_scrubber_math.dart';

void main() {
  const Duration fourHours = Duration(hours: 4);

  group('Arc scrubber math', () {
    test('maps the open arc endpoints to the beginning and end of media', () {
      expect(
        PhoneArcScrubberMath.positionForAngle(
          duration: fourHours,
          angleRadians: -math.pi / 2,
        ),
        Duration.zero,
      );
      expect(
        PhoneArcScrubberMath.positionForAngle(
          duration: fourHours,
          angleRadians: math.pi * 4 / 3,
        ),
        fourHours,
      );
    });

    test('fine radial scrubbing stays useful for long media', () {
      final position = PhoneArcScrubberMath.relativePosition(
        duration: fourHours,
        anchor: const Duration(hours: 2),
        angularDeltaRadians: math.pi / 6,
        precision: PhoneArcScrubPrecision.fine,
      );

      // 4h * (30°/330°)/32 ≈ 40909ms offset, allow 2ms rounding.
      expect(
        (position.inMilliseconds - const Duration(hours: 2, seconds: 40, milliseconds: 909).inMilliseconds).abs(),
        lessThan(2),
      );
    });

    test('handles -pi/pi seam without jump', () {
      // Start near end (-120deg) and delta crossing seam should be normalized.
      const Duration anchor = Duration(hours: 2);
      final double deltaCrossSeam = 0.2; // small forward delta across seam
      final Duration a = PhoneArcScrubberMath.relativePosition(
        duration: fourHours,
        anchor: anchor,
        angularDeltaRadians: deltaCrossSeam,
        precision: PhoneArcScrubPrecision.overview,
      );
      final Duration b = PhoneArcScrubberMath.relativePosition(
        duration: fourHours,
        anchor: anchor,
        angularDeltaRadians: deltaCrossSeam - 2 * math.pi,
        precision: PhoneArcScrubPrecision.overview,
      );
      // Normalized delta should make a and b equivalent (both small forward).
      expect((a.inMilliseconds - b.inMilliseconds).abs(), lessThan(5));
    });

    test('positionForAngle wraps -pi/pi correctly to tail', () {
      // -120deg in atan2 range is the tail, should map to end.
      expect(
        PhoneArcScrubberMath.positionForAngle(
          duration: fourHours,
          angleRadians: -2.0943951023931953, // -120deg
        ),
        fourHours,
      );
    });
  });

  group('Time lens scrubber math', () {
    test('uses smaller time windows as the thumb moves inward', () {
      expect(
        PhoneTimeLensScrubberMath.windowForDepth(
          duration: fourHours,
          normalizedDepth: 0.0,
        ),
        fourHours,
      );
      expect(
        PhoneTimeLensScrubberMath.windowForDepth(
          duration: fourHours,
          normalizedDepth: 1.0,
        ),
        const Duration(seconds: 30),
      );
    });

    test('clamps the local timeline preview to media bounds', () {
      expect(
        PhoneTimeLensScrubberMath.positionForVerticalDelta(
          duration: fourHours,
          anchor: const Duration(seconds: 10),
          verticalDelta: -1.0,
          window: const Duration(minutes: 5),
        ),
        Duration.zero,
      );
    });
  });
}

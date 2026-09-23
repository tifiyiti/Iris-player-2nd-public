import 'package:flutter_test/flutter_test.dart';
import 'package:iris/hooks/player/seek_clamp.dart';

void main() {
  group('clampSeekTarget', () {
    test('negative sub-second seek clamps to zero', () {
      expect(
        clampSeekTarget(
          const Duration(milliseconds: -500),
          const Duration(seconds: 100),
        ),
        Duration.zero,
      );
    });

    test('seek beyond total clamps to total', () {
      expect(
        clampSeekTarget(
          const Duration(milliseconds: 100501),
          const Duration(milliseconds: 100000),
        ),
        const Duration(milliseconds: 100000),
      );
    });

    test('in-range seek keeps millisecond precision', () {
      expect(
        clampSeekTarget(
          const Duration(milliseconds: 12345),
          const Duration(milliseconds: 100000),
        ),
        const Duration(milliseconds: 12345),
      );
    });

    test('sub-second negative near zero does not leak through', () {
      // Regression for the inSeconds bug: Duration(-500ms).inSeconds == 0,
      // so a seconds-based comparison missed it entirely.
      final target = clampSeekTarget(
        const Duration(milliseconds: -1),
        const Duration(milliseconds: 60000),
      );
      expect(target, Duration.zero);
    });

    test('exact total is preserved', () {
      expect(
        clampSeekTarget(
          const Duration(milliseconds: 60000),
          const Duration(milliseconds: 60000),
        ),
        const Duration(milliseconds: 60000),
      );
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/speed/model/speed_rate_wheel_math.dart';
import 'package:iris/globals.dart' show speedStops;

/// Dual-wheel speed picker math: the two wheels span 0.1..10.0 and the tenths
/// wheel domain follows the whole-number wheel (0 → no 0, 10 → only 0).
void main() {
  group('rateFineValues (coupling rules)', () {
    test('coarse 0 offers [1..9] — no 0.0', () {
      expect(rateFineValues(0), kRateFineZeroCoarse);
      expect(rateFineValues(0), isNot(contains(0)));
    });

    test('coarse 10 offers only [0] — no 10.1+', () {
      expect(rateFineValues(10), kRateFineTopCoarse);
      expect(rateFineValues(10), <int>[0]);
    });

    test('every other coarse offers [0..9]', () {
      for (final c in <int>[1, 2, 5, 9]) {
        expect(rateFineValues(c), kRateFineNormal, reason: 'coarse $c');
      }
    });
  });

  group('index / value mapping', () {
    test('rateFineValueAt clamps indices into the domain', () {
      expect(rateFineValueAt(0, 0), 1);
      expect(rateFineValueAt(0, -5), 1);
      expect(rateFineValueAt(0, 99), 9);
      expect(rateFineValueAt(10, 0), 0);
      expect(rateFineValueAt(5, 4), 4);
    });

    test('rateFineIndexForValue snaps out-of-domain tenths to the nearest', () {
      // 0 at coarse 0 snaps to 1 (index 0).
      expect(rateFineIndexForValue(0, 0), 0);
      expect(rateFineValueAt(0, rateFineIndexForValue(0, 0)), 1);
      // 7 at coarse 10 snaps to 0 (index 0).
      expect(rateFineIndexForValue(10, 7), 0);
      // In-domain values map to their own slot.
      for (var f = 0; f <= 9; f++) {
        expect(rateFineValueAt(3, rateFineIndexForValue(3, f)), f);
      }
    });
  });

  group('composeRate clamps to 0.1..10.0', () {
    test('lower boundary never reaches 0.0', () {
      expect(composeRate(0, 0), 0.1);
      expect(composeRate(0, 1), 0.1);
    });

    test('upper boundary never exceeds 10.0', () {
      expect(composeRate(10, 0), 10.0);
      expect(composeRate(10, 9), 10.0);
    });

    test('ordinary composition', () {
      expect(composeRate(1, 0), 1.0);
      expect(composeRate(2, 5), 2.5);
      expect(composeRate(9, 9), 9.9);
    });
  });

  group('splitRate', () {
    test('splits the boundaries', () {
      expect(splitRate(0.1), (coarse: 0, fine: 1));
      expect(splitRate(1.0), (coarse: 1, fine: 0));
      expect(splitRate(9.9), (coarse: 9, fine: 9));
      expect(splitRate(10.0), (coarse: 10, fine: 0));
    });

    test('round-trips every speedStops value', () {
      for (final double stop in speedStops) {
        final split = splitRate(stop);
        expect(split.coarse, inInclusiveRange(0, 10), reason: '$stop');
        expect(composeRate(split.coarse, split.fine), closeTo(stop, 1e-9),
            reason: '$stop must round-trip');
      }
    });
  });
}

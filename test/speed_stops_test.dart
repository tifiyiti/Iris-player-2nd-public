import 'package:flutter_test/flutter_test.dart';
import 'package:iris/globals.dart';

void main() {
  group('speedStops', () {
    test('covers 0.1..10.0 in uniform 0.1 steps', () {
      expect(speedStops.length, 100);
      expect(speedStops.first, 0.1);
      expect(speedStops.last, 10.0);
      for (var i = 0; i < speedStops.length; i++) {
        expect(speedStops[i], closeTo((i + 1) / 10, 1e-9),
            reason: 'speedStops[$i] must equal ${(i + 1) / 10}');
      }
    });

    test('is strictly ascending and contains 1.0', () {
      for (var i = 1; i < speedStops.length; i++) {
        expect(speedStops[i] > speedStops[i - 1], isTrue,
            reason: 'speedStops must be strictly ascending at index $i');
      }
      expect(speedStops.contains(1.0), isTrue);
    });
  });
}

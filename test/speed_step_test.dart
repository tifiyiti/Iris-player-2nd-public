import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/windows/desktop_keyboard/controller/speed_step.dart';
import 'package:iris/globals.dart';

void main() {
  group('nextSpeedStop', () {
    test('up moves one 0.1 stop faster', () {
      expect(nextSpeedStop(1.0, 1, speedStops), closeTo(1.1, 1e-9));
      expect(nextSpeedStop(0.5, 1, speedStops), closeTo(0.6, 1e-9));
    });

    test('down moves one 0.1 stop slower', () {
      expect(nextSpeedStop(1.0, -1, speedStops), closeTo(0.9, 1e-9));
      expect(nextSpeedStop(0.5, -1, speedStops), closeTo(0.4, 1e-9));
    });

    test('saturates at the max stop instead of wrapping', () {
      expect(nextSpeedStop(10.0, 1, speedStops), 10.0);
      expect(nextSpeedStop(9.95, 1, speedStops), 10.0);
    });

    test('saturates at the min stop instead of wrapping', () {
      expect(nextSpeedStop(0.1, -1, speedStops), 0.1);
      expect(nextSpeedStop(0.15, -1, speedStops), 0.1);
    });

    test('snaps an off-grid rate onto the next stop in the held direction', () {
      expect(nextSpeedStop(1.04, 1, speedStops), closeTo(1.1, 1e-9));
      expect(nextSpeedStop(1.04, -1, speedStops), closeTo(1.0, 1e-9));
    });

    test('works on an arbitrary stop list', () {
      const cycle = [0.5, 1.0, 1.5, 2.0];
      expect(nextSpeedStop(1.0, 1, cycle), 1.5);
      expect(nextSpeedStop(1.0, -1, cycle), 0.5);
      expect(nextSpeedStop(2.0, 1, cycle), 2.0);
    });
  });
}

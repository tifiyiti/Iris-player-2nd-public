import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/windows/desktop_keyboard/controller/ab_loop_engine.dart';

void main() {
  group('abEffectivePosition (VM coordinate guard)', () {
    test('no VM offset passes raw through', () {
      expect(
        abEffectivePosition(const Duration(seconds: 10)),
        const Duration(seconds: 10),
      );
    });

    test('seg1 raw 10s with 100s offset maps to virtual 110s', () {
      expect(
        abEffectivePosition(
          const Duration(seconds: 10),
          vmOffsetMs: 100000,
        ),
        const Duration(seconds: 110),
      );
    });

    test('switch in flight suppresses the tick (no loop on pre-seek 0)', () {
      expect(
        abEffectivePosition(
          Duration.zero,
          vmOffsetMs: 100000,
          suppress: true,
        ),
        isNull,
      );
    });
  });
}

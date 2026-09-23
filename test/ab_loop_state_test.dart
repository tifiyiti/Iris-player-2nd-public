import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/windows/desktop_keyboard/store/ab_loop_state.dart';

const _zero = Duration.zero;
const _a = Duration(seconds: 10);
const _b = Duration(seconds: 20);
const _beforeA = Duration(seconds: 5);

void main() {
  group('abReduce', () {
    test('setPointA rewrites A and disarms; stale B ahead is kept', () {
      final s1 = abReduce(const AbLoopState(), AbEvent.setPointA, _a);
      expect(s1.pointA, _a);
      expect(s1.pointB, isNull);
      expect(s1.enabled, isFalse);

      final s2 = abReduce(s1, AbEvent.setPointB, _b);
      expect(s2.enabled, isTrue); // B completes a valid loop → armed

      // New A before old B: B survives but the engine disarms until re-armed.
      final s3 = abReduce(
        abReduce(s2, AbEvent.setPointA, _beforeA),
        AbEvent.quickToggle,
        _beforeA,
      );
      expect(s3.pointB, _b);
      expect(s3.enabled, isTrue);
    });

    test('setPointB behind A is ignored', () {
      final s = abReduce(
        abReduce(const AbLoopState(), AbEvent.setPointA, _a),
        AbEvent.setPointB,
        _beforeA,
      );
      expect(s.pointB, isNull);
    });

    test('setPointB strictly after A arms the loop directly', () {
      final s = abReduce(const AbLoopState(pointA: _a), AbEvent.setPointB, _b);
      expect(s.enabled, isTrue);
      // zero-length loop (B == A) is rejected — prevents seek-storm (D2)
      final s2 = abReduce(const AbLoopState(pointA: _a), AbEvent.setPointB, _a);
      expect(s2.enabled, isFalse);
      expect(s2.pointB, isNull);
    });

    test('quickToggle arms only when disarmed-with-bounds; else resets', () {
      final partial = abReduce(const AbLoopState(), AbEvent.setPointA, _a);
      // only A known → nothing usable → reset
      expect(abReduce(partial, AbEvent.quickToggle, _a), const AbLoopState());

      final armed = abReduce(partial, AbEvent.setPointB, _b);
      expect(armed.enabled, isTrue);
      // already armed → quickToggle bails out completely
      expect(abReduce(armed, AbEvent.quickToggle, _zero), const AbLoopState());

      final disarmedButComplete =
          abReduce(armed, AbEvent.toggleSectionRepeat, _a);
      expect(disarmedButComplete.enabled, isFalse);
      expect(
        abReduce(disarmedButComplete, AbEvent.quickToggle, _a).enabled,
        isTrue,
      );
    });

    test('toggleSectionRepeat requires both bounds and flips in place', () {
      final partial = abReduce(const AbLoopState(), AbEvent.setPointA, _a);
      expect(abReduce(partial, AbEvent.toggleSectionRepeat, _a), partial);

      final full = partial.copyWith(pointB: _b);
      expect(abReduce(full, AbEvent.toggleSectionRepeat, _a).enabled, isTrue);
      expect(
        abReduce(full.copyWith(enabled: true), AbEvent.toggleSectionRepeat, _a)
            .enabled,
        isFalse,
      );
      expect(
        abReduce(full.copyWith(enabled: true), AbEvent.toggleSectionRepeat, _a)
            .pointA,
        _a,
      );
    });

    test('clear wipes everything', () {
      final full = abReduce(
        abReduce(const AbLoopState(), AbEvent.setPointA, _a),
        AbEvent.setPointB,
        _b,
      );
      expect(abReduce(full, AbEvent.clear, _zero), const AbLoopState());
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/phone/one_handed_scrubber/controller/phone_ring_dial_edge_lock.dart';

void main() {
  group('quadrantOf (canvas Y-down, mirrors legacy circle slider)', () {
    test('classifies the four screen quadrants', () {
      expect(quadrantOf(1, -1), ScrubQuadrant.q1); // top-right
      expect(quadrantOf(-1, -1), ScrubQuadrant.q2); // top-left
      expect(quadrantOf(-1, 1), ScrubQuadrant.q3); // bottom-left
      expect(quadrantOf(1, 1), ScrubQuadrant.q4); // bottom-right
    });

    test('axis-inclusive boundaries match the legacy classifier', () {
      expect(quadrantOf(0, -1), ScrubQuadrant.q1); // dx>=0 && dy<=0
      expect(quadrantOf(-1, 0), ScrubQuadrant.q2);
      expect(quadrantOf(1, 0), ScrubQuadrant.q1); // dy==0 counts as top
      expect(quadrantOf(0, 1), ScrubQuadrant.q4);
    });
  });

  group('InnerEdgeLockSession', () {
    const Duration dur = Duration(milliseconds: 10000);

    // Clock degrees: 0=12 o'clock (0%), 90=3 o'clock, 180=6 o'clock,
    // 270=9 o'clock, 330=11 o'clock (100%); 330..360 = dead gap.
    // Unit-circle pointers (y down): clock 45 → (+,-) Q1; 315 → (-,-) Q2;
    // 225 → (-,+) Q3; 135 → (+,+) Q4.
    int mappedMs(double clockDeg) =>
        (clockDeg / 330 * dur.inMilliseconds).round();

    test('first entry into a top quadrant locks and maps normally', () {
      final InnerEdgeLockSession s = InnerEdgeLockSession();
      expect(s.apply(dx: 1, dy: -1, clockDeg: 45, duration: dur),
          Duration(milliseconds: mappedMs(45)));
    });

    test('Q1 locked then pointer enters Q2 sticks at 0%', () {
      final InnerEdgeLockSession s = InnerEdgeLockSession();
      s.apply(dx: 1, dy: -1, clockDeg: 45, duration: dur);
      expect(s.apply(dx: -1, dy: -1, clockDeg: 315, duration: dur),
          Duration.zero);
      // Stays stuck while the pointer roams Q2 / the gap.
      expect(s.apply(dx: -1, dy: -1, clockDeg: 350, duration: dur),
          Duration.zero);
      expect(s.apply(dx: -2, dy: -0.5, clockDeg: 285, duration: dur),
          Duration.zero);
    });

    test('Q2 locked then pointer enters Q1 sticks at 100% (no wrap to 0)', () {
      final InnerEdgeLockSession s = InnerEdgeLockSession();
      s.apply(dx: -1, dy: 1, clockDeg: 225, duration: dur); // Q3 unlock path
      s.apply(dx: -1, dy: -1, clockDeg: 315, duration: dur); // locks Q2
      expect(s.apply(dx: 1, dy: -1, clockDeg: 45, duration: dur), dur);
      // Held in Q1 → still stuck at 100% (release commits via clampSeekTarget).
      expect(s.apply(dx: 1, dy: -1, clockDeg: 20, duration: dur), dur);
    });

    test('bottom quadrants unlock and remap continuously', () {
      final InnerEdgeLockSession s = InnerEdgeLockSession();
      s.apply(dx: 1, dy: -1, clockDeg: 45, duration: dur); // Q1 lock
      s.apply(dx: -1, dy: -1, clockDeg: 315, duration: dur); // stuck 0
      // Down through Q4: lock released, absolute mapping resumes.
      expect(s.apply(dx: 1, dy: 1, clockDeg: 135, duration: dur),
          Duration(milliseconds: mappedMs(135)));
      // Back up into Q1 re-locks; crossing into Q2 sticks again.
      s.apply(dx: 1, dy: -1, clockDeg: 45, duration: dur);
      expect(s.apply(dx: -1, dy: -1, clockDeg: 315, duration: dur),
          Duration.zero);
    });

    test('gap angle without a lock maps to the wrapped end (100%)', () {
      final InnerEdgeLockSession s = InnerEdgeLockSession();
      s.apply(dx: -1, dy: 1, clockDeg: 225, duration: dur); // Q3, no lock
      expect(s.apply(dx: -1, dy: -1, clockDeg: 350, duration: dur), dur);
    });

    test('clear() drops the lock', () {
      final InnerEdgeLockSession s = InnerEdgeLockSession();
      s.apply(dx: 1, dy: -1, clockDeg: 45, duration: dur); // Q1 lock
      s.clear();
      // Q2 pointer without a lock now maps (gap → 100%) instead of sticking 0.
      expect(s.apply(dx: -1, dy: -1, clockDeg: 315, duration: dur),
          Duration(milliseconds: mappedMs(315)));
    });
  });
}

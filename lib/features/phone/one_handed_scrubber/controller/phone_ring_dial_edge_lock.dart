/// Quadrant continuity + 0%/100% edge locks for the ring-dial drags,
/// ported verbatim from the legacy `ControlBarCircleSlider`
/// (`computeValueWithEdgeLock`).
/// The inner wayfinding ring maps the pointer's ABSOLUTE clock angle onto the
/// whole media timeline, so swinging the pointer across 12 o'clock would
/// otherwise wrap the position between ~0% and ~100% (Q1 ↔ Q2). The lock
/// rules make quadrant changes continuous:
///
/// - Q1 (top-right, near 0%) locked + pointer enters Q2 → stick at 0%.
/// - Q2 (top-left, near 100%) locked + pointer enters Q1 → stick at 100%
///   (the commit guard `clampSeekTarget` keeps a held 100% from advancing to
///   the next episode; only release commits).
/// - Bottom quadrants (Q3/Q4) release the lock — the free path between the
///   two arc ends.
/// - Entering a top quadrant with no lock acquires it.
library;

import 'package:iris/features/phone/one_handed_scrubber/controller/phone_ring_dial_math.dart';

enum ScrubQuadrant { q1, q2, q3, q4 }

/// Edge-lock stick outcome: arc start (0%) or arc end (100%).
enum EdgeLockStick { zero, end }

/// Canvas Y increases downward: q1 = top-right, q2 = top-left,
/// q3 = bottom-left, q4 = bottom-right. Axis-inclusive boundaries mirror the
/// legacy classifier (`dx >= 0 && dy <= 0` → q1, etc.).
ScrubQuadrant quadrantOf(double dx, double dy) {
  if (dx >= 0 && dy <= 0) return ScrubQuadrant.q1;
  if (dx < 0 && dy <= 0) return ScrubQuadrant.q2;
  if (dx < 0 && dy > 0) return ScrubQuadrant.q3;
  return ScrubQuadrant.q4;
}

/// Per-drag-session lock state for the inner ring's absolute clock mapping.
/// Fresh instance per pan (taps are intentional seeks and never consult it).
class InnerEdgeLockSession {
  ScrubQuadrant? _locked;

  bool get hasLock => _locked != null;

  /// Drops the lock (tap-style interactions, session reset).
  void clear() => _locked = null;

  /// Applies the edge-lock rules for one pointer update and returns the
  /// scrub target. [clockDeg] is the clock angle (0 = 12 o'clock, clockwise);
  /// [dx]/[dy] are pointer offsets from the ring centre (canvas Y-down).
  ///
  /// Stick outcomes are exact bounds — [Duration.zero] and [duration] — the
  /// caller's commit guard turns the latter into a safe sub-end seek.
  Duration apply({
    required double dx,
    required double dy,
    required double clockDeg,
    required Duration duration,
  }) {
    final EdgeLockStick? stuck = updateLock(dx: dx, dy: dy);
    if (stuck == EdgeLockStick.zero) return Duration.zero;
    if (stuck == EdgeLockStick.end) return duration;
    return PhoneRingDialEdgeLock.positionForInnerClock(clockDeg, duration);
  }

  /// Edge-lock state step shared by the duration-weighted ([apply]) and the
  /// equal-division VM ([applyEqualFraction]) mappings. Returns the stick
  /// outcome, or null when the pointer maps normally.
  EdgeLockStick? updateLock({required double dx, required double dy}) {
    final ScrubQuadrant current = quadrantOf(dx, dy);

    if (_locked != null) {
      if (_locked == ScrubQuadrant.q1 && current == ScrubQuadrant.q2) {
        // Crossing Q1 → Q2: return to the arc start (0%).
        return EdgeLockStick.zero;
      } else if (_locked == ScrubQuadrant.q2 &&
          current == ScrubQuadrant.q1) {
        // Crossing Q2 → Q1: hold the arc end (100%).
        return EdgeLockStick.end;
      }
      // Bottom quadrants release the lock — the free path.
      if (current == ScrubQuadrant.q3 || current == ScrubQuadrant.q4) {
        _locked = null;
      }
    }

    // Entering a top quadrant with no lock acquires it.
    if ((current == ScrubQuadrant.q1 || current == ScrubQuadrant.q2) &&
        _locked == null) {
      _locked = current;
    }
    return null;
  }

  /// Equal-division variant for the VM chunk ring: the same Q1↔Q2 stick rules
  /// on the [0,1] equal arc, gap angles resolving to the wrapped end (1.0).
  /// Callers map the returned fraction back onto the file's real span.
  double applyEqualFraction({
    required double dx,
    required double dy,
    required double clockDeg,
  }) {
    final EdgeLockStick? stuck = updateLock(dx: dx, dy: dy);
    if (stuck == EdgeLockStick.zero) return 0.0;
    if (stuck == EdgeLockStick.end) return 1.0;
    final ({double fraction, bool inGap}) hit =
        PhoneRingDialMath.fractionForInnerClock(clockDeg);
    return hit.inGap ? 1.0 : hit.fraction;
  }
}

/// Pure mapping helpers (delegates to `PhoneRingDialMath` so the lock and
/// the painter share one source of truth).
abstract final class PhoneRingDialEdgeLock {
  /// Absolute inner-ring mapping for a clock angle; gap angles (11→12
  /// o'clock) resolve to the wrapped end.
  static Duration positionForInnerClock(double clockDeg, Duration duration) =>
      PhoneRingDialMath.positionForInnerDragClock(clockDeg, duration);
}

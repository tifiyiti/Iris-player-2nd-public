/// File-local playable window of the CURRENT 副音 file under 仅当前 + 高同步.
///
/// 副音 exists only inside the foreground's 0–100%: `A` is the bg position
/// mapped to fg 00:00 (before it 副音 does not exist) and `B` the one mapped to
/// fg 100%. When the bg is longer than the mapped range, `[A, B]` is a strict
/// SUBSET of the file and the shared scrubbers must:
///
/// - clamp every user seek into it (never drag onto a position that would roll
///   the foreground past its end), and
/// - mark `A`/`B` so the unreachable region is visible instead of silently
///   snapping back, mirroring the Virtual-Media segment ticks.
///
/// Pure and testable: the runtime observer publishes the raw bounds, every
/// surface resolves them through [resolveBgSeekWindow].
library;

/// Resolved window. [hasLimit] is false when it spans the whole file — callers
/// must then draw NO marks (the reported "不要画" case).
class BgSeekWindow {
  const BgSeekWindow({
    required this.loMs,
    required this.hiMs,
    required this.durationMs,
  });

  /// First playable bg position (fg 00:00 mapped onto the bg axis).
  final int loMs;

  /// Last playable bg position (fg 100% mapped onto the bg axis).
  final int hiMs;

  /// Whole-file duration on the same axis.
  final int durationMs;

  /// True when some of the file sits outside `[loMs, hiMs]`.
  bool get hasLimit => durationMs > 0 && (loMs > 0 || hiMs < durationMs);

  /// `loMs` as a 0..1 fraction of the whole file (0 when unknown).
  double get floorFraction =>
      durationMs <= 0 ? 0.0 : (loMs / durationMs).clamp(0.0, 1.0);

  /// `hiMs` as a 0..1 fraction of the whole file (1 when unknown).
  double get ceilingFraction =>
      durationMs <= 0 ? 1.0 : (hiMs / durationMs).clamp(0.0, 1.0);

  /// Whole-file fraction of the window span.
  double get spanFraction => ceilingFraction - floorFraction;

  /// Maps a whole-file fraction to the 0..1 fraction INSIDE the window (for
  /// ring/circle geometry). Returns 0 when the window is empty.
  double toWindowFraction(double globalFraction) {
    final double span = spanFraction;
    if (span <= 0) return 0.0;
    return ((globalFraction - floorFraction) / span).clamp(0.0, 1.0);
  }
}

/// Resolves the playable window from the published raw bounds.
///
/// Unknown/null bounds mean "no limit" (the whole file). A malformed pair
/// (`floor > ceiling`, e.g. an empty playable window) collapses onto the
/// ceiling so the callers park at a single, valid point instead of inverting.
BgSeekWindow resolveBgSeekWindow({
  required Duration duration,
  int? floorMs,
  int? ceilingMs,
}) {
  final int dur = duration.inMilliseconds;
  if (dur <= 0) {
    return const BgSeekWindow(loMs: 0, hiMs: 0, durationMs: 0);
  }
  int lo = (floorMs ?? 0).clamp(0, dur);
  int hi = (ceilingMs ?? dur).clamp(0, dur);
  if (lo > hi) lo = hi;
  return BgSeekWindow(loMs: lo, hiMs: hi, durationMs: dur);
}

/// Clamps a whole-file ms target into the window (`no-op` when no limit).
int clampBgSeekMs(BgSeekWindow window, int ms) {
  if (window.durationMs <= 0) return ms;
  if (ms < window.loMs) return window.loMs;
  if (ms > window.hiMs) return window.hiMs;
  return ms;
}

/// Clamps a [Duration] target into the window.
Duration clampBgSeekDuration(BgSeekWindow window, Duration target) =>
    Duration(milliseconds: clampBgSeekMs(window, target.inMilliseconds));

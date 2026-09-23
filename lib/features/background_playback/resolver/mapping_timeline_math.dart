import 'dart:math' as math;

import 'package:iris/features/background_playback/model/domain/background_mapping.dart';

/// Pure mapping-timeline math shared by the runtime driver and the editor
/// (mirrored clamping/ratio rules live in exactly one place).
///
/// v1 alignment policy (段内速率对齐):
/// - Entering a playMedia segment seeks the background file to the
///   proportional position of the foreground inside the segment window;
/// - while the segment is active the background runs at
///   `fgRate × (bgSegmentLen / fgSegmentLen)` so the whole B window spans the
///   whole A window, clamped to a sane playback range.
abstract final class MappingTimelineMath {
  static const double kMinMappedRate = 0.5;
  static const double kMaxMappedRate = 2.0;

  /// The segment covering [fgPosMs] (half-open interval), or null = gap.
  static MappingSegment? segmentAt(
    List<MappingSegment> segments,
    int fgPosMs,
  ) {
    for (final s in segments) {
      if (fgPosMs >= s.fgStartMs && fgPosMs < s.fgEndMs) return s;
    }
    return null;
  }

  /// Segment identity for change/abort tracking.
  static String segmentKey(MappingSegment s) =>
      '${s.action.name}:${s.fgStartMs}:${s.fgEndMs}';

  /// Duration of the playMedia window (guard: silence has no bg).
  static int bgWindowMs(MappingSegment s) {
    final be = s.bgEndMs ?? 0;
    final bs = s.bgStartMs ?? 0;
    return (be - bs) < 0 ? 0 : be - bs;
  }

  static int fgWindowMs(MappingSegment s) => s.fgEndMs - s.fgStartMs;

  /// Recovers the background file duration the segment's normalized fields were
  /// authored against (`bgEnd / bgEndN`, else `bgStart / bgStartN`). Null when
  /// neither fraction is usable (silence, legacy rows, fresh replacements with
  /// no known new duration).
  ///
  /// A window authored normally never exceeds this value, so capping by it is a
  /// no-op for ordinary saves; after a bg swap that kept the span it truncates
  /// the now-uncovered tail.
  static int? bgTotalMsFromNorms(MappingSegment s) {
    final be = s.bgEndMs;
    final ben = s.bgEndN;
    if (be != null && be > 0 && ben != null && ben > 0) {
      return (be / ben).round();
    }
    final bs = s.bgStartMs;
    final bsn = s.bgStartN;
    if (bs != null && bs > 0 && bsn != null && bsn > 0) {
      return (bs / bsn).round();
    }
    return null;
  }

  /// The window actually covered by the background file: the stored window
  /// truncated to the real file duration ([bgDurMs] when known, else the
  /// recovered snapshot from [bgTotalMsFromNorms]). [covered] is false when the
  /// window starts past the file end, i.e. there is no audible bg at all.
  static ({int startMs, int endMs, bool covered}) effectiveBgWindow(
    MappingSegment s, {
    int? bgDurMs,
  }) {
    final bs = s.bgStartMs ?? 0;
    var be = s.bgEndMs ?? 0;
    final total =
        (bgDurMs != null && bgDurMs > 0) ? bgDurMs : bgTotalMsFromNorms(s);
    if (total != null && total > 0) be = math.min(be, total);
    if (be <= bs) return (startMs: bs, endMs: bs, covered: false);
    return (startMs: bs, endMs: be, covered: true);
  }

  /// Proportional background position for [fgPosMs] inside [s].
  static int bgTargetMsFor(MappingSegment s, int fgPosMs, {int? bgDurMs}) {
    final w = effectiveBgWindow(s, bgDurMs: bgDurMs);
    final bgLen = w.endMs - w.startMs;
    final fgLen = fgWindowMs(s);
    if (bgLen <= 0 || fgLen <= 0) return w.startMs;
    final rel = ((fgPosMs - s.fgStartMs) * bgLen) ~/ fgLen;
    return (w.startMs + rel).clamp(w.startMs, w.endMs);
  }

  /// Rate that makes the B window span the whole A window (clamped), measured
  /// over the COVERED window (see [effectiveBgWindow]).
  static double segmentRate(MappingSegment s, double fgRate, {int? bgDurMs}) {
    final w = effectiveBgWindow(s, bgDurMs: bgDurMs);
    final bgLen = w.endMs - w.startMs;
    final fgLen = fgWindowMs(s);
    if (bgLen <= 0 || fgLen <= 0) return fgRate;
    final raw = fgRate * bgLen / fgLen;
    return raw.clamp(kMinMappedRate, kMaxMappedRate);
  }

  /// True when the ratio is outside the clamp range (editor warns).
  static bool rateOutOfRange(MappingSegment s, double fgRate, {int? bgDurMs}) {
    final w = effectiveBgWindow(s, bgDurMs: bgDurMs);
    final bgLen = w.endMs - w.startMs;
    final fgLen = fgWindowMs(s);
    if (bgLen <= 0 || fgLen <= 0) return false;
    final raw = fgRate * bgLen / fgLen;
    return raw < kMinMappedRate || raw > kMaxMappedRate;
  }

  /// Normalized position helper: ms → 0..1 fraction of a total duration.
  static double? normOf(int ms, int? totalMs) =>
      (totalMs == null || totalMs <= 0) ? null : ms / totalMs;
}

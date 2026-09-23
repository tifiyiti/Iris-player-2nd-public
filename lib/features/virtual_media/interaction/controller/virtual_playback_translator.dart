import 'dart:math' as math;
import 'package:iris/features/virtual_media/model/domain/vm_item.dart';

/// Pure translation between virtual timeline and physical segments.
///
/// - `locate`: O(log n) via [VirtualMediaItem.locate], clamp past-end.
/// - Interval-random: touch precision insufficient → compute interval then
///   random within it (“不必总是试图一步计算出精度”).
/// - Competition: later segment wins at boundaries (prefix inclusive left).
class VirtualPlaybackTranslator {
  const VirtualPlaybackTranslator();

  /// Shared RNG for touch-slop jitter: avoids re-seeding a Random per tick
  /// and keeps the jitter distribution stable across seeks.
  static final math.Random _sharedRng = math.Random();

  /// Maps [virtualPosMs] onto `(segmentIndex, localMs)`.
  (int, int) locate(VirtualMediaItem item, int virtualPosMs) =>
      item.locate(virtualPosMs);

  /// Total virtual duration.
  int totalDurationMs(VirtualMediaItem item) => item.totalDurationMs;

  /// Virtual progress percent 0..1 (position / total).
  double progressFraction(VirtualMediaItem item, int virtualPosMs) {
    final total = item.totalDurationMs;
    if (total <= 0) return 0;
    return (virtualPosMs.clamp(0, total) / total).toDouble();
  }

  /// Inverse: fraction → virtualPosMs.
  int virtualPosForFraction(VirtualMediaItem item, double fraction) {
    final total = item.totalDurationMs;
    return (fraction.clamp(0.0, 1.0) * total).round();
  }

  /// Seek translation with touch-interval randomisation.
  ///
  /// [estimatedPixelWidth] may be null (fallback 320). [touchSlopPx] ~8px.
  /// Returns `(segmentIndex, localMs)` where localMs is jittered within the
  /// slop interval so repeated seeks don't always land on the same ms.
  (int, int) translateSeekWithJitter(
    VirtualMediaItem item,
    int virtualPosMs, {
    double? estimatedPixelWidth,
    double touchSlopPx = 8,
    math.Random? rng,
  }) {
    final (segIdx, local) = item.locate(virtualPosMs);
    final total = item.totalDurationMs;
    if (total <= 0) return (segIdx, local);
    final w = estimatedPixelWidth ?? 320;
    final intervalMs = (total / w * touchSlopPx).round().clamp(1, 2000);
    final half = intervalMs ~/ 2;
    final jitter = ((rng ?? _sharedRng).nextInt(intervalMs) - half);
    final seg = item.segments[segIdx];
    final segDur = seg.durationMs ?? 0;
    final jittered = (local + jitter).clamp(0, math.max(0, segDur - 1)) as int;
    return (segIdx, jittered);
  }

  /// Whether a drag from [fromVirtualMs] to [toVirtualMs] crosses segments.
  bool isCrossSegment(VirtualMediaItem item, int fromMs, int toMs) {
    final (a, _) = item.locate(fromMs);
    final (b, _) = item.locate(toMs);
    return a != b;
  }

  /// Preview for cross-segment drag (no actual seek yet).
  /// Returns display strings for the floating overlay
  /// “将跳转第X段 name 内 pos/dur 外 pos/total”.
  ({int segIdx, String name, int localMs, int segDurMs, int virtualMs, int totalMs})
      previewFor(VirtualMediaItem item, int virtualPosMs) {
    final (idx, local) = item.locate(virtualPosMs);
    final seg = item.segments[idx];
    return (
      segIdx: idx,
      name: seg.name,
      localMs: local,
      segDurMs: seg.durationMs ?? 0,
      virtualMs: virtualPosMs.clamp(0, item.totalDurationMs),
      totalMs: item.totalDurationMs,
    );
  }
}

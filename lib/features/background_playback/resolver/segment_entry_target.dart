/// Which saved segment the APB editor opens when the playhead is not sitting
/// inside one, and whether entering it needs to pull the playhead back.
///
/// Pure helpers so the entry decision is directly unit-tested; the view layer
/// only supplies the live durations and the activation-order list.
library;

import 'package:iris/features/background_playback/model/domain/background_mapping.dart';
import 'package:iris/features/background_playback/resolver/fg_display_window.dart';

/// The ACTIVE saved segment nearest to [fgPosMs] — distance to its interval.
///
/// Used when no segment covers the playhead: clicking APB must still show the
/// saved mapping rather than silently seeding a new one far away. Ties break on
/// the higher activation order, then the later start, mirroring
/// `ActiveMappingResolver`'s precedence so the picked target is deterministic.
MappingSegment? nearestActiveSegment(
  List<MappingSegment> segments,
  int fgPosMs,
) {
  MappingSegment? best;
  int bestDist = -1;
  for (final s in segments) {
    if (!s.isActive) continue;
    final int dist = fgPosMs < s.fgStartMs
        ? s.fgStartMs - fgPosMs
        : fgPosMs >= s.fgEndMs
            ? fgPosMs - s.fgEndMs
            : 0;
    if (best == null ||
        dist < bestDist ||
        (dist == bestDist && _nearerTie(s, best))) {
      best = s;
      bestDist = dist;
    }
  }
  return best;
}

bool _nearerTie(MappingSegment a, MappingSegment b) {
  if (a.activeSeq != b.activeSeq) return a.activeSeq > b.activeSeq;
  return a.fgStartMs > b.fgStartMs;
}

/// Whether the playhead lies OUTSIDE the zoom window that frames the edited
/// segment — i.e. the editor cannot show the segment and the dot at once, so
/// entering must pull the playhead back to A.
///
/// The checked window is the align editor's own ([FgDisplayWindowMath.forSpan]),
/// matching what will actually be displayed. Unknown durations (<= 0) never
/// report "far": the editor holds a placeholder until they arrive.
bool playheadOutsideSegmentWindow({
  required int fgDurMs,
  required int bgDurMs,
  required double zoom,
  required bool pushBg,
  required int fgPosMs,
  required int segmentStartMs,
  required int segmentEndMs,
}) {
  if (fgDurMs <= 0 || bgDurMs <= 0) return false;
  final FgDisplayWindow win = FgDisplayWindowMath.forSpan(
    fgDurMs: fgDurMs,
    bgDurMs: bgDurMs,
    zoom: zoom,
    pushBg: pushBg,
    fgPosMs: fgPosMs,
    spanStartMs: segmentStartMs,
    spanEndMs: segmentEndMs,
    requestedStartMs: fgPosMs,
  );
  return fgPosMs < win.startMs || fgPosMs > win.endMs;
}

import 'package:iris/features/virtual_media/model/domain/vm_item.dart';

/// Nominal duration (ms) assigned to a segment whose real duration could
/// NOT be obtained. Such segments occupy this small unit on the virtual
/// timeline and render as a RED bar on scrubber marks ("获取失败就自行分配
/// 一个小的视频红条单位表示失败").
const int kVmUnknownSegmentUnitMs = 60 * 1000;

/// True when a segment still needs its duration resolved: no usable
/// duration AND not already carrying the nominal estimated unit.
bool vmSegmentNeedsDuration(VirtualSegment s) {
  final d = s.durationMs;
  if (d != null && d > 0) return false;
  return !s.durationEstimated;
}

/// First segment index needing duration resolution, or -1 when done.
int firstUnresolvedVmDurationIndex(List<VirtualSegment> segments) {
  for (var i = 0; i < segments.length; i++) {
    if (vmSegmentNeedsDuration(segments[i])) return i;
  }
  return -1;
}

/// Applies one probe outcome to [segments] at [index], returning a NEW list
/// (input untouched). A null/non-positive [realDurationMs] means the probe
/// failed: the segment receives the nominal red-bar unit and is flagged
/// [VirtualSegment.durationEstimated] so it is never re-probed.
List<VirtualSegment> applyVmProbeOutcome(
    List<VirtualSegment> segments, int index, int? realDurationMs) {
  final effective =
      (realDurationMs == null || realDurationMs <= 0) ? null : realDurationMs;
  final out = [...segments];
  out[index] = effective == null
      ? out[index].withDuration(kVmUnknownSegmentUnitMs,
          durationEstimated: true)
      : out[index].withDuration(effective);
  return out;
}

/// Rebuilds [item] with [segments]; identity fields are preserved.
VirtualMediaItem rebuildVmItem(
    VirtualMediaItem item, List<VirtualSegment> segments) {
  return VirtualMediaItem(
    ruleId: item.ruleId,
    scopeKey: item.scopeKey,
    rootPath: item.rootPath,
    displayIndex: item.displayIndex,
    displayName: item.displayName,
    segments: segments,
  );
}

/// Plans one probe batch for the playback-time duration backfill.
///
/// Collects up to [batchSize] segment indices at/after [cursor] that still
/// need durations AND are not network segments (FTP/WebDAV/network probes
/// issued mid-playback stall the session — the scan flow skips them too).
/// `done: true` means no local work remains (network unknowns are left for
/// the playing segment's lazy backfill, never probed here). Pure.
({List<int> indices, bool done}) planVmBackfillBatch(
  List<VirtualSegment> segments, {
  required int cursor,
  required bool Function(VirtualSegment seg) isNetwork,
  int batchSize = 32,
}) {
  final size = batchSize <= 0 ? 32 : batchSize;
  final indices = <int>[];
  for (var i = cursor;
      i < segments.length && indices.length < size;
      i++) {
    final s = segments[i];
    if (!vmSegmentNeedsDuration(s)) continue;
    if (isNetwork(s)) continue;
    indices.add(i);
  }
  return (indices: indices, done: indices.isEmpty);
}

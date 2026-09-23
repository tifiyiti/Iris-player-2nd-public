import 'package:iris/features/virtual_media/model/domain/vm_item.dart';

/// PotPlayer-style scrubber decoration for an active virtual session:
/// thin vertical ticks at every segment boundary (small bars on the axis,
/// `pot player多文件播放.png` style).  Red spans mark probe-failed segments
/// whose duration is the nominal 60s estimated unit — this is a FAILURE
/// signal: normal playback must NOT show red bars; if red appears an error
/// log is emitted so the probe failure can be reported and fixed.
/// See [computeVmScrubberMarks] for the failure-span contract.
///
/// Pure view-model shared by ALL progress surfaces (normal track shape,
/// dial ring inner ring, simple circle arc) — VM-inactive sessions yield
/// empty marks and every slider renders untouched.
class VmScrubberMarks {
  /// Boundary fractions in (0,1), strictly increasing.
  final List<double> boundaries;

  /// Timeline spans occupied by probe-failed segments.
  final List<({double start, double end})> failedSpans;

  const VmScrubberMarks(
      {required this.boundaries, required this.failedSpans});

  static const empty =
      VmScrubberMarks(boundaries: [], failedSpans: []);

  bool get isEmpty => boundaries.isEmpty && failedSpans.isEmpty;
}

VmScrubberMarks computeVmScrubberMarks(VirtualMediaItem? item) {
  if (item == null || item.segments.isEmpty || item.totalDurationMs <= 0) {
    return VmScrubberMarks.empty;
  }
  final total = item.totalDurationMs;
  const eps = 0.0001;
  final boundaries = <double>[];
  var last = 0.0;
  final failed = <({double start, double end})>[];

  for (var i = 0; i < item.segments.length; i++) {
    final start = item.offsetOf(i) / total;
    if (i > 0 && start > eps && start < 1 - eps && start - last > eps) {
      boundaries.add(start);
      last = start;
    }
    final seg = item.segments[i];
    if (seg.durationEstimated) {
      final end = (item.offsetOf(i + 1) / total).clamp(start, 1.0);
      if (end - start > eps) {
        failed.add((start: start, end: end));
      }
    }
  }
  return VmScrubberMarks(
      boundaries: boundaries, failedSpans: failed);
}

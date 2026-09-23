import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/virtual_media/model/domain/vm_item.dart';
import 'package:iris/features/virtual_media/view/vm_scrubber_marks.dart';

VirtualSegment seg(String path,
    {int? durationMs, bool estimated = false}) {
  final parts = path.split('/');
  return VirtualSegment(
    mediaKey: 'st1:$path',
    storageId: 'st1',
    path: parts,
    name: parts.last,
    parentPath:
        parts.length <= 1 ? '' : parts.sublist(0, parts.length - 1).join('/'),
    durationMs: durationMs,
    durationEstimated: estimated,
  );
}

VirtualMediaItem itemOf(List<VirtualSegment> segments) => VirtualMediaItem(
      ruleId: 'r',
      scopeKey: 'r|k|1',
      rootPath: 'k',
      displayIndex: 1,
      displayName: 'k',
      segments: segments,
    );

void main() {
  test('null item → empty marks (no session)', () {
    expect(computeVmScrubberMarks(null).isEmpty, isTrue);
  });

  test('all-unknown timeline (total 0) → empty marks', () {
    final m = computeVmScrubberMarks(
        itemOf([seg('k/1.mp4'), seg('k/2.mp4')]));
    expect(m.isEmpty, isTrue);
  });

  test('boundaries at cumulative fractions, none at edges', () {
    final m = computeVmScrubberMarks(itemOf([
      seg('k/1.mp4', durationMs: 1000),
      seg('k/2.mp4', durationMs: 2000),
      seg('k/3.mp4', durationMs: 500),
    ]));
    expect(m.boundaries, [1000 / 3500, 3000 / 3500]);
    expect(m.failedSpans, isEmpty);
  });

  test('estimated segments produce failed spans over their extent', () {
    final m = computeVmScrubberMarks(itemOf([
      seg('k/1.mp4', durationMs: 1000),
      seg('k/2.mp4',
          durationMs: 60000,
          estimated: true), // red-bar unit at [1s, 61s]
      seg('k/3.mp4', durationMs: 1000),
    ]));
    expect(m.boundaries, [1000 / 62000, 61000 / 62000]);
    expect(m.failedSpans.single.start, closeTo(1000 / 62000, 1e-9));
    expect(m.failedSpans.single.end, closeTo(61000 / 62000, 1e-9));
  });

  test('zero-length pending segments do not duplicate boundaries', () {
    // During probing, unknown segments carry duration 0 — their boundary
    // sits exactly on the previous one and must be deduped.
    final m = computeVmScrubberMarks(itemOf([
      seg('k/1.mp4', durationMs: 1000),
      seg('k/2.mp4'),
      seg('k/3.mp4'),
      seg('k/4.mp4', durationMs: 1000),
    ]));
    expect(m.boundaries, [1000 / 2000]);
  });
}

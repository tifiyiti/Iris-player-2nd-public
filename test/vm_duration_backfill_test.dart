import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/virtual_media/model/domain/vm_item.dart';
import 'package:iris/features/virtual_media/playback/vm_duration_backfill.dart';

VirtualSegment seg(String path, {int? durationMs, bool estimated = false}) {
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

void main() {
  test('needsDuration: unknown or zero needs, real and estimated do not', () {
    expect(vmSegmentNeedsDuration(seg('a/1.mp4')), isTrue);
    expect(vmSegmentNeedsDuration(seg('a/2.mp4', durationMs: 0)), isTrue);
    expect(vmSegmentNeedsDuration(seg('a/3.mp4', durationMs: 5000)), isFalse);
    expect(
        vmSegmentNeedsDuration(
            seg('a/4.mp4', durationMs: 60000, estimated: true)),
        isFalse);
  });

  test('firstUnresolved scans in order and terminates', () {
    final list = [
      seg('a/1.mp4', durationMs: 1000),
      seg('a/2.mp4'),
      seg('a/3.mp4', durationMs: 60000, estimated: true),
      seg('a/4.mp4', durationMs: 0),
    ];
    expect(firstUnresolvedVmDurationIndex(list), 1);
    expect(
        firstUnresolvedVmDurationIndex([
          seg('a/1.mp4', durationMs: 1),
          seg('a/2.mp4', durationMs: 2),
        ]),
        -1);
  });

  test('applyVmProbeOutcome: success writes real duration', () {
    final list = [seg('a/1.mp4', durationMs: 1), seg('a/2.mp4')];
    final out = applyVmProbeOutcome(list, 1, 12345);
    expect(out[1].durationMs, 12345);
    expect(out[1].durationEstimated, isFalse);
    // Input untouched.
    expect(list[1].durationMs, isNull);
  });

  test('applyVmProbeOutcome: failure assigns nominal red-bar unit once', () {
    final list = [seg('a/1.mp4')];
    final failed = applyVmProbeOutcome(list, 0, null);
    expect(failed[0].durationMs, kVmUnknownSegmentUnitMs);
    expect(failed[0].durationEstimated, isTrue);
    // Zero counts as a failed probe too.
    final zero = applyVmProbeOutcome(list, 0, 0);
    expect(zero[0].durationMs, kVmUnknownSegmentUnitMs);
    expect(zero[0].durationEstimated, isTrue);
  });

  test('rebuildVmItem preserves identity and recomputes the timeline', () {    final item = VirtualMediaItem(
      ruleId: 'r',
      scopeKey: 'r|k|1',
      rootPath: 'k',
      displayIndex: 1,
      displayName: 'k',
      segments: [seg('k/1.mp4'), seg('k/2.mp4', durationMs: 1000)],
    );
    expect(item.totalDurationMs, 1000);
    final patched = applyVmProbeOutcome(item.segments, 0, 500);
    final rebuilt = rebuildVmItem(item, patched);
    expect(rebuilt.ruleId, 'r');
    expect(rebuilt.scopeKey, 'r|k|1');
    expect(rebuilt.displayName, 'k');
    expect(rebuilt.totalDurationMs, 1500);
    // locate() reflects the corrected prefix sums (0,500,1500).
    expect(rebuilt.locate(499), (0, 499));
    expect(rebuilt.locate(500), (1, 0));
    expect(rebuilt.locate(1499), (1, 999));
  });

  group('planVmBackfillBatch', () {
    VirtualSegment bseg(String name,
        {String storageId = 'st1', int? durationMs, bool estimated = false}) {
      return VirtualSegment(
        mediaKey: '$storageId:$name',
        storageId: storageId,
        path: [name],
        name: name,
        parentPath: '',
        durationMs: durationMs,
        durationEstimated: estimated,
      );
    }

    test('collects unresolved local segments up to batchSize', () {
      final list = [
        bseg('1.mp4', durationMs: 1000),
        bseg('2.mp4'),
        bseg('3.mp4'),
        bseg('4.mp4'),
      ];
      final plan = planVmBackfillBatch(list,
          cursor: 0, isNetwork: (_) => false, batchSize: 2);
      expect(plan.done, isFalse);
      expect(plan.indices, [1, 2]);
    });

    test('skips network segments without probing them', () {
      final list = [
        bseg('1.mp4', storageId: 'ftp1'),
        bseg('2.mp4'),
      ];
      final plan = planVmBackfillBatch(list,
          cursor: 0, isNetwork: (s) => s.storageId == 'ftp1');
      expect(plan.done, isFalse);
      expect(plan.indices, [1]);
    });

    test('done when only network unknowns remain', () {
      final list = [bseg('1.mp4', storageId: 'ftp1')];
      final plan = planVmBackfillBatch(list,
          cursor: 0, isNetwork: (s) => s.storageId == 'ftp1');
      expect(plan.done, isTrue);
      expect(plan.indices, isEmpty);
    });

    test('done when everything resolved', () {
      final list = [bseg('1.mp4', durationMs: 5)];
      final plan = planVmBackfillBatch(list,
          cursor: 0, isNetwork: (_) => false);
      expect(plan.done, isTrue);
    });

    test('cursor resumes past already-scanned segments', () {
      final list = [bseg('1.mp4'), bseg('2.mp4'), bseg('3.mp4')];
      final plan = planVmBackfillBatch(list,
          cursor: 2, isNetwork: (_) => false, batchSize: 32);
      expect(plan.indices, [2]);
    });
  });
}

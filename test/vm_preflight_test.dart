import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/virtual_media/model/domain/vm_item.dart';
import 'package:iris/features/virtual_media/resolver/vm_preflight.dart';

VirtualSegment seg(String name, {int? durationMs}) {
  final path = ['Shorts', name];
  return VirtualSegment(
    mediaKey: 'st1:Shorts/$name',
    storageId: 'st1',
    path: path,
    name: name,
    parentPath: 'Shorts',
    durationMs: durationMs,
  );
}

VirtualMediaItem item(String scope, List<VirtualSegment> segs) {
  return VirtualMediaItem(
    ruleId: 'r1',
    scopeKey: scope,
    rootPath: 'Shorts',
    displayIndex: 1,
    displayName: 'item',
    segments: segs,
  );
}

void main() {
  test('single feasible segment is VALID virtual (maps as single-file feed)', () {
    final partitioned = partitionVmItems([
      item('r1|Shorts|#1', [seg('1.mp4', durationMs: 60000)]),
    ]);
    expect(partitioned.valid, hasLength(1));
    expect(partitioned.failByKey, isEmpty);
  });

  test('any zero/unknown duration fails the whole group', () {
    final partitioned = partitionVmItems([
      item('r1|Shorts|#1', [
        seg('1.mp4', durationMs: 60000),
        seg('2.mp4', durationMs: null),
      ]),
    ]);
    expect(partitioned.valid, isEmpty);
    expect(partitioned.failByKey.keys,
        containsAll(['st1:Shorts/1.mp4', 'st1:Shorts/2.mp4']));
    expect(partitioned.failByKey.values.first.reason,
        VmFailReason.zeroDuration);
  });

  test('all-feasible multi-segment group stays valid', () {
    final partitioned = partitionVmItems([
      item('r1|Shorts|#1', [
        seg('1.mp4', durationMs: 1000),
        seg('2.mp4', durationMs: 2000),
      ]),
    ]);
    expect(partitioned.valid, hasLength(1));
    expect(partitioned.failByKey, isEmpty);
  });

  test('empty input partitions to empty without throwing', () {
    final partitioned = partitionVmItems(const []);
    expect(partitioned.valid, isEmpty);
    expect(partitioned.failByKey, isEmpty);
  });
}

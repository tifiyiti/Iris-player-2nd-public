import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/virtual_media/model/domain/vm_item.dart';
import 'package:iris/features/virtual_media/resolver/vm_preflight.dart';
import 'package:iris/features/virtual_media/service/vm_overlay_service.dart';

VirtualMediaItem item(String scope) {
  return VirtualMediaItem(
    ruleId: 'r1',
    scopeKey: scope,
    rootPath: 'Shorts',
    displayIndex: 1,
    displayName: 'item',
    segments: [
      VirtualSegment(
        mediaKey: 'st1:Shorts/1.mp4',
        storageId: 'st1',
        path: const ['Shorts', '1.mp4'],
        name: '1.mp4',
        parentPath: 'Shorts',
      ),
    ],
  );
}

void main() {
  final service = VirtualMediaService.instance;

  tearDown(() => service.invalidate());

  test('dismissed scope suppresses the prompt until invalidate', () {
    expect(service.isScanDismissed('r1|A|#1'), isFalse);
    service.dismissScanScope('r1|A|#1');
    expect(service.isScanDismissed('r1|A|#1'), isTrue);
    service.invalidate();
    expect(service.isScanDismissed('r1|A|#1'), isFalse);
  });

  test('removeFailFor clears only the scanned keys', () {
    service.setLastFail({
      'k1': const VmFailInfo(
          reason: VmFailReason.zeroDuration,
          detail: 'd1',
          scopeKey: 's',
          ruleId: 'r'),
      'k2': const VmFailInfo(
          reason: VmFailReason.zeroDuration,
          detail: 'd2',
          scopeKey: 's',
          ruleId: 'r'),
    });
    service.removeFailFor({'k1'});
    expect(service.failInfoFor('k1'), isNull);
    expect(service.failInfoFor('k2'), isNotNull);
  });

  test('failed groups are stashed by scope for the scan flow', () {
    final group = item('r1|Shorts|#1');
    service.setLastFail({
      'st1:Shorts/1.mp4': const VmFailInfo(
          reason: VmFailReason.zeroDuration,
          detail: 'd',
          scopeKey: 'r1|Shorts|#1',
          ruleId: 'r1'),
    }, failedGroups: [group]);
    expect(service.failedGroupForScope('r1|Shorts|#1'), same(group));
    expect(service.failedGroupForScope('nope'), isNull);
  });

  test('partition exposes failed groups alongside the fail map', () {
    final partitioned = partitionVmItems([item('r1|Shorts|#1')]);
    expect(partitioned.valid, isEmpty);
    expect(partitioned.failed, hasLength(1));
    expect(partitioned.failByKey.keys, ['st1:Shorts/1.mp4']);
  });
}

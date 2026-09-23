import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/model/enum/basic_enum.dart';
import 'package:iris/features/media_library/model/media_lib/media_node.dart';
import 'package:iris/features/scenario_playback/model/domain/effective_playback_item.dart';
import 'package:iris/features/scenario_playback/model/domain/playback_occurrence_id.dart';
import 'package:iris/features/virtual_media/model/domain/vm_rule.dart';
import 'package:iris/features/virtual_media/model/enum/vm_enums.dart';
import 'package:iris/features/virtual_media/resolver/vm_overlay.dart';
import 'package:iris/features/virtual_media/resolver/vm_stream_merge.dart';

EffectivePlaybackItem streamItem(
  String path, {
  String storage = 'st1',
  int? sizeInBytes,
  int? durationMs = 60000,
}) {
  final parts = path.split('/');
  final f = MediaNode.file(
    id: '$storage:$path',
    storageId: storage,
    path: parts,
    parentPath:
        parts.length <= 1 ? null : parts.sublist(0, parts.length - 1).join('/'),
    name: parts.last,
    mediaType: MediaType.video,
    sizeInBytes: sizeInBytes,
    durationMs: durationMs,
  );
  return EffectivePlaybackItem(
    media: f,
    scenarioId: 's1',
    available: true,
    virtualIndex: 0,
    occurrenceId: PlaybackOccurrenceId(storageId: storage, path: path),
  );
}

VirtualMediaRule rule({
  int maxItemCount = 10,
  bool skipSingleSegment = false,
}) {
  return VirtualMediaRule(
    id: 'r1',
    name: 'R',
    matchMode: VmMatchMode.specifiedDirRecursive,
    paths: const ['Shorts'],
    boundary: VmBoundaryMode.ignoreDirs,
    sortField: VmSortField.fileName,
    sortDir: SortDirection.asc,
    useDurationCap: false,
    useCountCap: true,
    maxItemCount: maxItemCount,
    titleTags: const [VmTitleTag.seq],
    useExcludeOverlong: false,
    skipSingleSegment: skipSingleSegment,
  );
}

void main() {
  test('segments carry file size through the stream adapter', () {
    final groups = resolveGroupsForStream([
      streamItem('Shorts/1.mp4', sizeInBytes: 100),
      streamItem('Shorts/2.mp4', sizeInBytes: 200),
    ], [rule()]);
    final group = groups.inOrder.single;
    expect(group.segments.map((s) => s.sizeInBytes).toList(), [100, 200]);
    expect(group.totalSizeBytes, 300);
  });

  test('totalSizeBytes treats unknown sizes as 0', () {
    final groups = resolveGroupsForStream([
      streamItem('Shorts/1.mp4', sizeInBytes: 100),
      streamItem('Shorts/2.mp4', sizeInBytes: null),
    ], [rule()]);
    expect(groups.inOrder.single.totalSizeBytes, 100);
  });

  test('overlay exposes merged totals plus segment count', () {
    final stream = [
      streamItem('Shorts/1.mp4', sizeInBytes: 100, durationMs: 1000),
      streamItem('Shorts/2.mp4', sizeInBytes: 200, durationMs: 2000),
      streamItem('Shorts/3.mp4', sizeInBytes: 300, durationMs: 3000),
    ];
    final groups = resolveGroupsForStream(stream, [rule()]);
    final merged = applyVmOverlay(stream, groups.byKey);

    expect(merged, hasLength(1));
    final rep = merged.single;
    expect(rep.virtualMerged, isTrue);
    expect(rep.vmTotalSizeBytes, 600);
    expect(rep.vmTotalDurationMs, 6000);
    expect(rep.vmSegmentCount, 3);
  });

  test('ordinary rows keep null merged totals', () {
    final stream = [streamItem('Other/1.mp4', sizeInBytes: 100)];
    final groups = resolveGroupsForStream(stream, [rule()]);
    final merged = applyVmOverlay(stream, groups.byKey);
    expect(merged.single.virtualMerged, isFalse);
    expect(merged.single.vmTotalSizeBytes, isNull);
    expect(merged.single.vmTotalDurationMs, isNull);
    expect(merged.single.vmSegmentCount, isNull);
  });

  test('existing overlay emits without size keep totals null-safe', () {
    final stream = [
      streamItem('Shorts/1.mp4', sizeInBytes: null, durationMs: 1000),
      streamItem('Shorts/2.mp4', sizeInBytes: null, durationMs: 2000),
    ];
    final groups = resolveGroupsForStream(stream, [rule()]);
    final merged = applyVmOverlay(stream, groups.byKey);
    expect(merged.single.vmTotalSizeBytes, 0);
    expect(merged.single.vmTotalDurationMs, 3000);
    expect(merged.single.vmSegmentCount, 2);
  });
}

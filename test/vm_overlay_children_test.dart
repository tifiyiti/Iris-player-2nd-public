import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/model/enum/basic_enum.dart';
import 'package:iris/features/media_library/model/media_lib/media_node.dart';
import 'package:iris/features/scenario_playback/model/domain/effective_playback_item.dart';
import 'package:iris/features/scenario_playback/model/domain/playback_occurrence_id.dart';
import 'package:iris/features/virtual_media/model/domain/vm_item.dart';
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

VirtualMediaRule rule() => VirtualMediaRule(
      id: 'r1',
      name: 'R',
      matchMode: VmMatchMode.specifiedDirRecursive,
      paths: const ['Shorts'],
      boundary: VmBoundaryMode.ignoreDirs,
      sortField: VmSortField.fileName,
      sortDir: SortDirection.asc,
      useDurationCap: false,
      useCountCap: true,
      maxItemCount: 32,
      titleTags: const [VmTitleTag.seq],
      useExcludeOverlong: false,
      skipSingleSegment: false,
    );

VirtualSegment seg(
  String path, {
  int? durationMs,
  int? sizeInBytes,
  bool estimated = false,
}) {
  final parts = path.split('/');
  return VirtualSegment(
    mediaKey: 'st1:$path',
    storageId: 'st1',
    path: parts,
    name: parts.last,
    parentPath:
        parts.length <= 1 ? '' : parts.sublist(0, parts.length - 1).join('/'),
    durationMs: durationMs,
    sizeInBytes: sizeInBytes,
    durationEstimated: estimated,
  );
}

void main() {
  test('merged representative carries ordered compact child descriptors', () {
    final stream = [
      streamItem('Shorts/1.mp4', sizeInBytes: 100, durationMs: 1000),
      streamItem('Shorts/2.mp4', sizeInBytes: 200, durationMs: 2000),
      streamItem('Shorts/3.mp4', sizeInBytes: 300, durationMs: 3000),
    ];
    final groups = resolveGroupsForStream(stream, [rule()]);
    final rep = applyVmOverlay(stream, groups.byKey).single;

    expect(rep.virtualMerged, isTrue);
    expect(rep.vmChildren, hasLength(3));
    expect(
      rep.vmChildren.map((c) => c.mediaKey).toList(),
      ['st1:Shorts/1.mp4', 'st1:Shorts/2.mp4', 'st1:Shorts/3.mp4'],
    );
    expect(rep.vmChildren.map((c) => c.name).toList(), ['1.mp4', '2.mp4', '3.mp4']);
    expect(rep.vmChildren.map((c) => c.durationMs).toList(), [1000, 2000, 3000]);
    expect(rep.vmChildren.map((c) => c.sizeInBytes).toList(), [100, 200, 300]);
    expect(rep.vmChildren.every((c) => !c.durationEstimated), isTrue);
  });

  test('ordinary rows carry no children', () {
    final stream = [streamItem('Other/1.mp4', sizeInBytes: 100)];
    final groups = resolveGroupsForStream(stream, [rule()]);
    final merged = applyVmOverlay(stream, groups.byKey);
    expect(merged.single.virtualMerged, isFalse);
    expect(merged.single.vmChildren, isEmpty);
  });

  test('estimated duration flag is preserved on children', () {
    final stream = [
      streamItem('Shorts/1.mp4', durationMs: 1000),
      streamItem('Shorts/2.mp4', durationMs: 2000),
    ];
    // Group order comes from group.segments (the play order), so a hand-built
    // group lets us assert the estimated flag flows through unchanged.
    final group = groupOf('r1|Shorts|1', [
      seg('Shorts/1.mp4', durationMs: 1000),
      seg('Shorts/2.mp4', durationMs: 60000, estimated: true),
    ]);
    final merged = applyVmOverlay(stream, {
      'st1:Shorts/1.mp4': group,
      'st1:Shorts/2.mp4': group,
    });
    expect(merged.single.vmChildren, hasLength(2));
    expect(merged.single.vmChildren[0].durationEstimated, isFalse);
    expect(merged.single.vmChildren[1].durationEstimated, isTrue);
  });

  test('children follow group play order, not raw run order', () {
    final stream = [
      streamItem('Shorts/2.mp4', sizeInBytes: 200),
      streamItem('Shorts/1.mp4', sizeInBytes: 100),
    ];
    final group = groupOf('r1|Shorts|1', [
      seg('Shorts/1.mp4', sizeInBytes: 100),
      seg('Shorts/2.mp4', sizeInBytes: 200),
    ]);
    final merged = applyVmOverlay(stream, {
      'st1:Shorts/1.mp4': group,
      'st1:Shorts/2.mp4': group,
    });
    expect(
      merged.single.vmChildren.map((c) => c.mediaKey).toList(),
      ['st1:Shorts/1.mp4', 'st1:Shorts/2.mp4'],
    );
  });
}

VirtualMediaItem groupOf(String scopeKey, List<VirtualSegment> segments) =>
    VirtualMediaItem(
      ruleId: 'r1',
      scopeKey: scopeKey,
      rootPath: 'Shorts',
      displayIndex: 1,
      displayName: '合并',
      segments: segments,
    );

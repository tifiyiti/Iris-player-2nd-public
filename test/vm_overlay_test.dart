import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/model/media_lib/media_node.dart';
import 'package:iris/features/scenario_playback/model/domain/effective_playback_item.dart';
import 'package:iris/features/scenario_playback/model/domain/playback_occurrence_id.dart';
import 'package:iris/features/virtual_media/model/domain/vm_item.dart';
import 'package:iris/features/virtual_media/resolver/vm_overlay.dart';

EffectivePlaybackItem eff(String storageId, String path, String name,
    {int occurrence = 0, int virtualIndex = 0}) {
  final parts = path.split('/');
  return EffectivePlaybackItem(
    media: MediaNode.file(
      id: '$storageId:$path',
      storageId: storageId,
      path: parts,
      name: name,
      mediaType: MediaType.video,
    ),
    scenarioId: 's1',
    virtualIndex: virtualIndex,
    occurrenceId: PlaybackOccurrenceId(
        storageId: storageId, path: path, occurrenceIndex: occurrence),
  );
}

VirtualSegment seg(String path, {int? durationMs}) {
  final parts = path.split('/');
  return VirtualSegment(
    mediaKey: 'st1:$path',
    storageId: 'st1',
    path: parts,
    name: parts.last,
    parentPath:
        parts.length <= 1 ? '' : parts.sublist(0, parts.length - 1).join('/'),
    durationMs: durationMs,
  );
}

VirtualMediaItem groupOf(String scopeKey, List<VirtualSegment> segments,
        {String title = '合并视频'}) =>
    VirtualMediaItem(
      ruleId: 'r',
      scopeKey: scopeKey,
      rootPath: 'k',
      displayIndex: 1,
      displayName: title,
      segments: segments,
    );

void main() {
  test('empty groups → stream untouched (identity)', () {
    final stream = [eff('st1', 'a/1.mp4', '1.mp4')];
    expect(applyVmOverlay(stream, const {}), same(stream));
  });

  test('consecutive group members collapse to ONE titled entry', () {
    final stream = [
      eff('st1', 'a/1.mp4', '1.mp4', virtualIndex: 0),
      eff('st1', 'a/2.mp4', '2.mp4', virtualIndex: 1),
      eff('st1', 'b/9.mp4', '9.mp4', virtualIndex: 2),
    ];
    final groups = {
      'st1:a/1.mp4': groupOf('r|a|1',
          [seg('a/1.mp4'), seg('a/2.mp4')], title: '剧集A · 1'),
      'st1:a/2.mp4': groupOf('r|a|1',
          [seg('a/1.mp4'), seg('a/2.mp4')], title: '剧集A · 1'),
    };
    final merged = applyVmOverlay(stream, groups);
    expect(merged, hasLength(2));
    expect(merged[0].media.name, '剧集A · 1');
    // Representative keeps the FIRST segment's identity.
    expect(merged[0].mediaKey, 'st1:a/1.mp4');
    expect(merged[0].occurrenceId.occurrenceIndex, 0);
    // Marked as a merged representative; ordinary rows stay unmarked.
    expect(merged[0].virtualMerged, isTrue);
    expect(merged[1].virtualMerged, isFalse);
    // Virtual indices reassigned.
    expect(merged[1].virtualIndex, 1);
    expect(merged[0].virtualIndex, 0);
  });

  test('members fold by group identity, not by stream adjacency', () {
    final stream = [
      eff('st1', 'a/1.mp4', '1.mp4'),
      eff('st1', 'x/other.mp4', 'other.mp4'),
      eff('st1', 'a/2.mp4', '2.mp4'),
    ];
    final g = groupOf('r|a|1', [seg('a/1.mp4'), seg('a/2.mp4')]);
    final merged = applyVmOverlay(stream, {
      'st1:a/1.mp4': g,
      'st1:a/2.mp4': g,
      'st1:x/other.mp4': g,
    });
    // All three belong to the group → one entry, whatever separates them.
    expect(merged, hasLength(1));
    expect(merged.single.media.name, '合并视频');
    expect(merged.single.mediaKey, 'st1:a/1.mp4');
  });

  test('non-consecutive members fold into ONE row at the earliest member', () {
    final stream = [
      eff('st1', 'a/1.mp4', '1.mp4'),
      eff('st1', 'x/other.mp4', 'other.mp4'),
      eff('st1', 'a/2.mp4', '2.mp4'),
    ];
    final g = groupOf('r|a|1', [seg('a/1.mp4'), seg('a/2.mp4')]);
    final merged = applyVmOverlay(stream, {
      'st1:a/1.mp4': g,
      'st1:a/2.mp4': g,
    });
    // `other.mp4` is not a member and keeps its own row; the two members fold
    // into ONE row placed at the first one — a group never appears twice, and
    // its children follow the GROUP's order rather than the stream's.
    expect(merged, hasLength(2));
    expect(merged[0].mediaKey, 'st1:a/1.mp4');
    expect(merged[0].media.name, '合并视频');
    expect(merged[1].mediaKey, 'st1:x/other.mp4');
    expect(merged.map((e) => e.virtualIndex).toList(), [0, 1]);
    expect(merged[0].vmChildren.map((c) => c.mediaKey).toList(),
        ['st1:a/1.mp4', 'st1:a/2.mp4']);
  });
}

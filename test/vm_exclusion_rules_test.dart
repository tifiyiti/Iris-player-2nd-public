import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/model/enum/basic_enum.dart';
import 'package:iris/features/media_library/model/media_lib/media_node.dart';
import 'package:iris/features/scenario_playback/model/domain/effective_playback_item.dart';
import 'package:iris/features/scenario_playback/model/domain/playback_occurrence_id.dart';
import 'package:iris/features/virtual_media/model/domain/vm_item.dart';
import 'package:iris/features/virtual_media/model/domain/vm_rule.dart';
import 'package:iris/features/virtual_media/model/enum/vm_enums.dart';
import 'package:iris/features/virtual_media/resolver/vm_resolver.dart';
import 'package:iris/features/virtual_media/resolver/vm_stream_merge.dart';

const int kMin = 60 * 1000;

VirtualSegment seg(String path, {int? durationMs, String storage = 'st1'}) {
  final parts = path.split('/');
  return VirtualSegment(
    mediaKey: '$storage:$path',
    storageId: storage,
    path: parts,
    name: parts.last,
    parentPath:
        parts.length <= 1 ? '' : parts.sublist(0, parts.length - 1).join('/'),
    durationMs: durationMs,
  );
}

VirtualMediaRule rule({
  VmMatchMode matchMode = VmMatchMode.specifiedDirRecursive,
  List<String> paths = const ['Shorts'],
  VmBoundaryMode boundary = VmBoundaryMode.ignoreDirs,
  bool useExcludeOverlong = true,
  int maxSingleDurationMinutes = kVmDefaultMaxSingleDurationMinutes,
  bool skipSingleSegment = true,
}) {
  return VirtualMediaRule(
    id: 'r1',
    name: 'R',
    matchMode: matchMode,
    paths: paths,
    boundary: boundary,
    sortField: VmSortField.fileName,
    sortDir: SortDirection.asc,
    useDurationCap: false,
    useCountCap: false,
    useExcludeOverlong: useExcludeOverlong,
    maxSingleDurationMinutes: maxSingleDurationMinutes,
    skipSingleSegment: skipSingleSegment,
    titleTags: const [VmTitleTag.seq],
  );
}

EffectivePlaybackItem streamItem(String path,
    {String storage = 'st1', int? durationMs = 60 * 1000}) {
  final parts = path.split('/');
  final f = MediaNode.file(
    id: '$storage:$path',
    storageId: storage,
    path: parts,
    parentPath:
        parts.length <= 1 ? null : parts.sublist(0, parts.length - 1).join('/'),
    name: parts.last,
    mediaType: MediaType.video,
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

void main() {
  group('batch resolver — overlong exclusion', () {
    test('drops segments strictly longer than the threshold', () {
      final items = resolveVirtualMedia(
        rules: [rule(maxSingleDurationMinutes: 35)],
        library: [
          seg('Shorts/1.mp4', durationMs: 10 * kMin),
          seg('Shorts/2.mp4', durationMs: 36 * kMin), // over 35 → out
          seg('Shorts/3.mp4', durationMs: 20 * kMin),
        ],
      );
      expect(items, hasLength(1));
      expect(items.first.segments.map((s) => s.name).toList(),
          ['1.mp4', '3.mp4']);
    });

    test('exactly at threshold is kept (strictly greater excluded)', () {
      final items = resolveVirtualMedia(
        rules: [rule(maxSingleDurationMinutes: 35)],
        library: [
          seg('Shorts/1.mp4', durationMs: 35 * kMin),
          seg('Shorts/2.mp4', durationMs: 10 * kMin),
        ],
      );
      expect(items.single.segments.map((s) => s.name).toList(),
          ['1.mp4', '2.mp4']);
    });

    test('unknown duration (null / 0) is never excluded', () {
      final items = resolveVirtualMedia(
        rules: [rule(maxSingleDurationMinutes: 35)],
        library: [
          seg('Shorts/1.mp4', durationMs: null),
          seg('Shorts/2.mp4', durationMs: 0),
          seg('Shorts/3.mp4', durationMs: 10 * kMin),
        ],
      );
      expect(items.single.segments, hasLength(3));
    });

    test('disabled switch keeps overlong segments', () {
      final items = resolveVirtualMedia(
        rules: [rule(maxSingleDurationMinutes: 35, useExcludeOverlong: false)],
        library: [
          seg('Shorts/1.mp4', durationMs: 90 * kMin),
          seg('Shorts/2.mp4', durationMs: 10 * kMin),
        ],
      );
      expect(items.single.segments, hasLength(2));
    });
  });

  group('batch resolver — single-segment chunks', () {
    test('a lone matching file produces no virtual item', () {
      final items = resolveVirtualMedia(
        rules: [rule()],
        library: [seg('Shorts/only.mp4', durationMs: 5 * kMin)],
      );
      expect(items, isEmpty);
    });

    test('single-segment directory chunks are dropped independently', () {
      // sameDirOnly: each directory chunks on its own; A has 1 file, B has 2.
      final items = resolveVirtualMedia(
        rules: [
          rule(
            matchMode: VmMatchMode.specifiedDirRecursive,
            boundary: VmBoundaryMode.sameDirOnly,
          )
        ],
        library: [
          seg('Shorts/A/only.mp4', durationMs: 5 * kMin),
          seg('Shorts/B/1.mp4', durationMs: 5 * kMin),
          seg('Shorts/B/2.mp4', durationMs: 5 * kMin),
        ],
      );
      expect(items, hasLength(1));
      expect(items.single.rootPath, 'Shorts/B');
    });

    test('disabled switch keeps the lone-segment virtual item', () {
      final items = resolveVirtualMedia(
        rules: [rule(skipSingleSegment: false)],
        library: [seg('Shorts/only.mp4', durationMs: 5 * kMin)],
      );
      expect(items, hasLength(1));
      expect(items.single.segments, hasLength(1));
    });
  });

  group('stream merge — shared semantics', () {
    test('overlong segments never enter a group; the rest still merge', () {
      final groups = resolveGroupsForStream([
        streamItem('Shorts/1.mp4', durationMs: 10 * kMin),
        streamItem('Shorts/2.mp4', durationMs: 10 * kMin),
        streamItem('Shorts/3.mp4', durationMs: 40 * kMin), // over the 35 cap
        streamItem('Shorts/4.mp4', durationMs: 10 * kMin),
      ], [rule(maxSingleDurationMinutes: 35)]);
      // The overlong file is not a candidate for the rule at all, so it stays
      // an ordinary row — while every in-scope file that IS a candidate merges
      // into one group (the old "an overlong file cuts the run in two" rule
      // was an artifact of deriving groups from stream runs).
      expect(groups.byKey.keys,
          unorderedEquals(['st1:Shorts/1.mp4', 'st1:Shorts/2.mp4', 'st1:Shorts/4.mp4']));
      expect(groups.byKey.containsKey('st1:Shorts/3.mp4'), isFalse);
      expect(groups.inOrder.single.segments, hasLength(3));
    });

    test('lone matching stream file yields no group', () {
      final groups = resolveGroupsForStream(
        [streamItem('Shorts/only.mp4')],
        [rule()],
      );
      expect(groups.isEmpty, isTrue);
    });

    test('disabled skips keep single-segment groups', () {
      final groups = resolveGroupsForStream(
        [streamItem('Shorts/only.mp4')],
        [rule(skipSingleSegment: false, useExcludeOverlong: false)],
      );
      expect(groups.inOrder.single.segments, hasLength(1));
    });
  });
}

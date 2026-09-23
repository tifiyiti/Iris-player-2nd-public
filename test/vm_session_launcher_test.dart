import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/model/enum/basic_enum.dart';
import 'package:iris/features/media_library/model/media_lib/media_node.dart';
import 'package:iris/features/scenario_playback/model/domain/effective_playback_item.dart';
import 'package:iris/features/scenario_playback/model/domain/playback_occurrence_id.dart';
import 'package:iris/features/virtual_media/model/domain/vm_rule.dart';
import 'package:iris/features/virtual_media/model/enum/vm_enums.dart';
import 'package:iris/features/virtual_media/playback/vm_session_launcher.dart';

EffectivePlaybackItem streamItem(
  String path, {
  String storage = 'st1',
  bool available = true,
  int? durationMs = 60000,
  int occurrenceIndex = 0,
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
    durationMs: durationMs,
  );
  return EffectivePlaybackItem(
    media: f,
    scenarioId: 's1',
    available: available,
    virtualIndex: 0,
    occurrenceId: PlaybackOccurrenceId(
      storageId: storage,
      path: path,
      occurrenceIndex: occurrenceIndex,
    ),
  );
}

VirtualMediaRule rule({
  String id = 'r1',
  VmMatchMode matchMode = VmMatchMode.specifiedDirRecursive,
  List<String> paths = const ['Shorts'],
  VmBoundaryMode boundary = VmBoundaryMode.ignoreDirs,
  VmSortField sortField = VmSortField.fileName,
  SortDirection sortDir = SortDirection.asc,
  bool useDurationCap = false,
  bool useCountCap = true,
  int maxItemCount = 2,
}) {
  return VirtualMediaRule(
    id: id,
    name: 'R',
    matchMode: matchMode,
    paths: paths,
    boundary: boundary,
    sortField: sortField,
    sortDir: sortDir,
    useDurationCap: useDurationCap,
    useCountCap: useCountCap,
    maxItemCount: maxItemCount,
    titleTags: const [VmTitleTag.seq],
  );
}

void main() {
  group('planVmSessionStart', () {
    test('virtual member → plan targets its group with segment 0 start', () {
      // 4 stream members + count cap 2 → two virtual bodies ([1,2],[3,4]).
      final stream = [
        streamItem('Shorts/1.mp4'),
        streamItem('Shorts/2.mp4'),
        streamItem('Shorts/3.mp4'),
        streamItem('Shorts/4.mp4'),
      ];
      final plan = planVmSessionStart(
        storageId: 'st1',
        path: 'Shorts/3.mp4',
        rules: [rule()],
        stream: stream,
      );
      expect(plan, isNotNull);
      expect(plan!.queue, hasLength(2));
      // Sibling queue = all in-order virtual bodies of the rule; entry is the
      // SECOND body (scopeKey of [3.mp4, 4.mp4]).
      expect(plan.queue[1].segments.map((s) => s.name).toList(),
          ['3.mp4', '4.mp4']);
      expect(plan.queueIndex, 1);
      expect(plan.segmentIndex, 0);
      // Mirrors provider.play(): a session always opens from segment start
      // (legacy per-file DB resume must not leak into the virtual timeline).
      expect(plan.initialLocalMs, 0);
    });

    test('non-virtual member → null (ordinary single-file playback)', () {
      final stream = [
        streamItem('Shorts/1.mp4'),
        streamItem('Movies/9.mp4'),
      ];
      final plan = planVmSessionStart(
        storageId: 'st1',
        path: 'Movies/9.mp4',
        rules: [rule()],
        stream: stream,
      );
      expect(plan, isNull);
    });

    test('no enabled rules → null', () {
      final stream = [streamItem('Shorts/1.mp4')];
      final plan = planVmSessionStart(
        storageId: 'st1',
        path: 'Shorts/1.mp4',
        rules: const [],
        stream: stream,
      );
      expect(plan, isNull);
    });

    test('preflight-degraded member (unknown duration) → null', () {
      final stream = [
        streamItem('Shorts/1.mp4', durationMs: 60000),
        streamItem('Shorts/2.mp4', durationMs: null),
      ];
      // 2.mp4 is the degraded member: it cannot merge → ordinary playback.
      final plan = planVmSessionStart(
        storageId: 'st1',
        path: 'Shorts/2.mp4',
        rules: [rule(maxItemCount: 100)],
        stream: stream,
      );
      expect(plan, isNull);
    });

    test('group feasibility is decided upstream; plan keeps resolved group',
        () {
      final stream = [
        streamItem('Shorts/1.mp4', durationMs: 60000),
        streamItem('Shorts/2.mp4', durationMs: 60000),
      ];
      final plan = planVmSessionStart(
        storageId: 'st1',
        path: 'Shorts/1.mp4',
        rules: [rule()],
        stream: stream,
      );
      expect(plan, isNotNull);
      expect(plan!.queueIndex, 0);
      expect(plan.queue.single.segments, hasLength(2));
    });

    test('most-recently-watched file restores segment + intra-segment offset',
        () {
      final stream = [
        streamItem('Shorts/1.mp4', durationMs: 60000),
        streamItem('Shorts/2.mp4', durationMs: 60000),
        streamItem('Shorts/3.mp4', durationMs: 90000),
        streamItem('Shorts/4.mp4', durationMs: 90000),
      ];
      final at = DateTime.utc(2026, 8, 1);
      final plan = planVmSessionStart(
        storageId: 'st1',
        path: 'Shorts/3.mp4',
        rules: [rule()],
        stream: stream,
        // SECOND body's SECOND segment (4.mp4) watched last, at 12s.
        progressByKey: {
          'st1:Shorts/3.mp4': (
            positionMs: 30000,
            completed: false,
            lastPlayedAt: at,
          ),
          'st1:Shorts/4.mp4': (
            positionMs: 12000,
            completed: false,
            lastPlayedAt: at.add(const Duration(minutes: 5)),
          ),
        },
      );
      expect(plan, isNotNull);
      expect(plan!.queueIndex, 1);
      expect(plan.segmentIndex, 1);
      expect(plan.initialLocalMs, 12000);
    });

    test('no usable progress in the group degrades to segment 0 start', () {
      final stream = [
        streamItem('Shorts/1.mp4', durationMs: 60000),
        streamItem('Shorts/2.mp4', durationMs: 60000),
        streamItem('Shorts/3.mp4', durationMs: 90000),
        streamItem('Shorts/4.mp4', durationMs: 90000),
      ];
      final plan = planVmSessionStart(
        storageId: 'st1',
        path: 'Shorts/3.mp4',
        rules: [rule()],
        stream: stream,
        // Progress only for a segment absent from this group (chunk reshaped).
        progressByKey: {
          'st1:Shorts/999.mp4': (
            positionMs: 12000,
            completed: false,
            lastPlayedAt: DateTime.utc(2026, 8, 1),
          ),
        },
      );
      expect(plan, isNotNull);
      expect(plan!.segmentIndex, 0);
      expect(plan.initialLocalMs, 0);
    });
  });

  group('planVmSessionStart bookmark target', () {
    test('preferRecency: a different recency file beats the row bookmark', () {
      // Cold start after a session crossed into another segment: the persisted
      // occurrence is the scenario's ROW (the group anchor), while the file the
      // user last watched must win.
      final stream = [
        streamItem('Shorts/1.mp4', durationMs: 60000),
        streamItem('Shorts/2.mp4', durationMs: 60000),
      ];
      final at = DateTime.utc(2026, 8, 1);
      final plan = planVmSessionStart(
        storageId: 'st1',
        path: 'Shorts/1.mp4',
        rules: [rule(maxItemCount: 100)],
        stream: stream,
        progressByKey: {
          'st1:Shorts/2.mp4': (
            positionMs: 12000,
            completed: false,
            lastPlayedAt: at,
          ),
        },
        targetMediaKey: 'st1:Shorts/1.mp4',
        preferRecency: true,
      );
      expect(plan, isNotNull);
      expect(plan!.segmentIndex, 1,
          reason: 'the last-watched file wins over the row anchor');
      expect(plan.initialLocalMs, 12000);
    });

    test('preferRecency: the bookmark still pins a duplicated COPY', () {
      // Same file twice (allowDuplicate): recency cannot tell the copies apart
      // (one progress row per file), so the persisted occurrence must.
      final stream = [
        streamItem('Shorts/1.mp4', occurrenceIndex: 0),
        streamItem('Shorts/1.mp4', occurrenceIndex: 1),
      ];
      final at = DateTime.utc(2026, 8, 1);
      final plan = planVmSessionStart(
        storageId: 'st1',
        path: 'Shorts/1.mp4',
        rules: [rule(maxItemCount: 100)],
        stream: stream,
        progressByKey: {
          'st1:Shorts/1.mp4': (
            positionMs: 30000,
            completed: false,
            lastPlayedAt: at,
          ),
        },
        targetMediaKey: 'st1:Shorts/1.mp4',
        targetOccurrenceIndex: 1,
        preferRecency: true,
      );
      expect(plan, isNotNull);
      expect(plan!.segmentIndex, 1);
      expect(plan.initialLocalMs, isNull,
          reason: 'a located copy defers to the file\'s own saved progress');
    });

    test('target file wins over the most-recently-watched segment', () {
      final stream = [
        streamItem('Shorts/1.mp4', durationMs: 60000),
        streamItem('Shorts/2.mp4', durationMs: 60000),
      ];
      final at = DateTime.utc(2026, 8, 1);
      final plan = planVmSessionStart(
        storageId: 'st1',
        path: 'Shorts/1.mp4',
        rules: [rule(maxItemCount: 100)],
        stream: stream,
        // Recency points at 2.mp4, but the bookmark asks for 1.mp4.
        progressByKey: {
          'st1:Shorts/2.mp4': (
            positionMs: 12000,
            completed: false,
            lastPlayedAt: at,
          ),
        },
        targetMediaKey: 'st1:Shorts/1.mp4',
      );
      expect(plan, isNotNull);
      expect(plan!.segmentIndex, 0);
      // A located target defers to the file's own saved progress (native
      // resume), so no intra-segment offset is pre-computed here.
      expect(plan.initialLocalMs, isNull);
    });

    test('target absent from the group falls back to recency', () {
      final stream = [
        streamItem('Shorts/1.mp4', durationMs: 60000),
        streamItem('Shorts/2.mp4', durationMs: 60000),
      ];
      final at = DateTime.utc(2026, 8, 1);
      final plan = planVmSessionStart(
        storageId: 'st1',
        path: 'Shorts/1.mp4',
        rules: [rule(maxItemCount: 100)],
        stream: stream,
        progressByKey: {
          'st1:Shorts/2.mp4': (
            positionMs: 12000,
            completed: false,
            lastPlayedAt: at,
          ),
        },
        targetMediaKey: 'st1:Shorts/999.mp4',
      );
      expect(plan, isNotNull);
      expect(plan!.segmentIndex, 1);
      expect(plan.initialLocalMs, 12000);
    });

    test('duplicate target opens the TAPPED occurrence, not the first', () {
      // `allowDuplicate`: the same file appears twice with occurrence 0/1.
      // The bookmark must resolve to the tapped occurrence.
      final stream = [
        streamItem('Shorts/1.mp4', occurrenceIndex: 0),
        streamItem('Shorts/1.mp4', occurrenceIndex: 1),
      ];
      final plan = planVmSessionStart(
        storageId: 'st1',
        path: 'Shorts/1.mp4',
        rules: [rule(maxItemCount: 100)],
        stream: stream,
        targetMediaKey: 'st1:Shorts/1.mp4',
        targetOccurrenceIndex: 1,
      );
      expect(plan, isNotNull);
      expect(plan!.segmentIndex, 1,
          reason: 'occurrence 1 must not collapse to the first occurrence');
      // The same target WITHOUT an occurrence keeps the legacy media-key match.
      final legacy = planVmSessionStart(
        storageId: 'st1',
        path: 'Shorts/1.mp4',
        rules: [rule(maxItemCount: 100)],
        stream: stream,
        targetMediaKey: 'st1:Shorts/1.mp4',
      );
      expect(legacy!.segmentIndex, 0);
    });
  });

  test('session queue follows the DISPLAYED merged order across rules', () {
    // Two independent rules whose groups INTERLEAVE in the scenario stream
    // (A, A, B, B, A, A). Each rule owns ONE group over its own files, so the
    // displayed merged list is [A, B] and the session's sibling queue must
    // match it — natural auto-advance lands on the row the user actually sees
    // next (B) instead of walking into a second, imaginary A row.
    final stream = [
      streamItem('A/1.mp4'),
      streamItem('A/2.mp4'),
      streamItem('B/1.mp4'),
      streamItem('B/2.mp4'),
      streamItem('A/3.mp4'),
      streamItem('A/4.mp4'),
    ];
    final plan = planVmSessionStart(
      storageId: 'st1',
      path: 'A/1.mp4',
      rules: [
        rule(id: 'r1', paths: const ['A'], maxItemCount: 100),
        rule(id: 'r2', paths: const ['B'], maxItemCount: 100),
      ],
      stream: stream,
    );
    expect(plan, isNotNull);
    expect(plan!.queue.map((g) => g.ruleId).toList(), ['r1', 'r2'],
        reason: 'queue order must equal the displayed merged order');
    expect(plan.queueIndex, 0);
    expect(plan.queue[0].segments.map((s) => s.name).toList(),
        ['1.mp4', '2.mp4', '3.mp4', '4.mp4'],
        reason: 'one rule chunk spans all of its files, interleaved or not');
    expect(plan.queue[1].ruleId, 'r2');
    expect(plan.queue[1].segments.map((s) => s.name).toList(),
        ['1.mp4', '2.mp4']);
  });
}

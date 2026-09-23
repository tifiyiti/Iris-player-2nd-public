import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/scenario_playback/model/db/dao/scenario_queue_index_dao.dart';
import 'package:iris/features/scenario_playback/resolver/scenario_queue_builder.dart';
import 'package:iris/features/scenario_playback/resolver/shared_base_order.dart';
import 'package:iris/features/scenario_playback/resolver/shared_row_overlay.dart';

/// The compact overlay must be LOSSLESS — rows AND group members — or the read
/// path would serve a different queue (or a group missing its members).
///
/// The round trip is pure Dart on purpose: the DB-backed oracle this used to
/// compare against was the v43 row tables, which ⑥ retired. What the RESOLVER's
/// own plan produces from the overlay is pinned byte for byte by the frozen
/// goldens (`scenario_shared_index_golden_test.dart`).
void main() {
  void expectRowsEqual(
      List<QueueEntryRow> actual, List<QueueEntryRow> expected) {
    expect(actual.length, expected.length, reason: 'row count');
    for (var i = 0; i < expected.length; i++) {
      final a = actual[i];
      final e = expected[i];
      expect(a.anchorRank, e.anchorRank, reason: 'row $i anchorRank');
      expect(a.isGroup, e.isGroup, reason: 'row $i isGroup');
      expect(a.groupId, e.groupId, reason: 'row $i groupId');
      expect(a.mediaNodeId, e.mediaNodeId, reason: 'row $i mediaNodeId');
      expect(a.occurrenceIndex, e.occurrenceIndex, reason: 'row $i occurrence');
      expect(a.flags, e.flags, reason: 'row $i flags');
      expect(a.placeholderStorageId, e.placeholderStorageId,
          reason: 'row $i placeholderStorageId');
      expect(a.placeholderPath, e.placeholderPath,
          reason: 'row $i placeholderPath');
    }
  }

  void expectMembersEqual(
      List<GroupMemberRow> actual, List<GroupMemberRow> expected) {
    expect(actual.length, expected.length, reason: 'member count');
    for (var i = 0; i < expected.length; i++) {
      expect(actual[i].inGroupRank, expected[i].inGroupRank);
      expect(actual[i].mediaNodeId, expected[i].mediaNodeId);
      expect(actual[i].occurrenceIndex, expected[i].occurrenceIndex);
    }
  }

  group('round-trip (pure Dart)', () {
    test('file / group members / absent member / placeholder / flags survive',
        () {
      final order = Int32List.fromList([1, 2, 3, 4, 5, 6]);
      final base = SharedBaseOrder.build(slices: [
        SharedOrderSlice.of(orderKey: 'k', order: order, select: (_) => true)
      ]);
      final entries = <QueueEntryRow>[
        const QueueEntryRow(anchorRank: 0, isGroup: false, mediaNodeId: 1),
        // Ranks 1 and 2 are absorbed by the group anchored at 3.
        const QueueEntryRow(
            anchorRank: 3, isGroup: true, groupId: 'r1|/m|#1'),
        const QueueEntryRow(
          anchorRank: 4,
          isGroup: false,
          mediaNodeId: 5,
          occurrenceIndex: 2,
          flags: QueueRowFlags.explicit,
        ),
        const QueueEntryRow(
          anchorRank: 5,
          isGroup: false,
          mediaNodeId: -1,
          placeholderStorageId: 'st1',
          placeholderPath: 'A/gone.mp4',
        ),
      ];
      final groupsById = <String, GroupRow>{
        'r1|/m|#1': const GroupRow(
          groupId: 'r1|/m|#1',
          ruleId: 'r1',
          anchorRoot: '/m',
          displaySeq: 1,
          segmentCount: 3,
          totalDurationMs: 0,
          totalSizeBytes: 0,
          members: [
            GroupMemberRow(inGroupRank: 0, mediaNodeId: 1),
            GroupMemberRow(inGroupRank: 1, mediaNodeId: 2, occurrenceIndex: 1),
            // A rule-chunk member that is NOT in this scenario's stream.
            GroupMemberRow(inGroupRank: 2, mediaNodeId: -1),
          ],
        ),
      };

      final overlay = SharedRowOverlay.fromPlan(
        baseCount: 6,
        entries: entries,
        groupsById: groupsById,
      );

      expect(overlay.absorbed.count, 2);
      expect(overlay.absorbed[1], isTrue);
      expect(overlay.absorbed[2], isTrue);
      expect(overlay.absorbed[3], isFalse);
      expect(overlay.groupRows.single.anchorRank, 3);
      expect(overlay.groupRows.single.groupId, 'r1|/m|#1');
      expect(overlay.groupRows.single.members, [1, 2, -1]);
      expect(overlay.groupRows.single.memberOccurrence, {1: 1});
      expect(overlay.occurrence, {4: 2});
      // Raw flags preserved (not collapsed to a bool).
      expect(overlay.flags, {4: QueueRowFlags.explicit});
      expect(overlay.placeholders[5]?.path, 'A/gone.mp4');

      expectRowsEqual(overlay.toEntries(base), entries);
      expectMembersEqual(overlay.groupRows.single.toMemberRows(),
          groupsById['r1|/m|#1']!.members);
    });

    test('a dense file-only order has no absorbed ranks and no groups', () {
      final order = Int32List.fromList([7, 8, 9]);
      final base = SharedBaseOrder.build(slices: [
        SharedOrderSlice.of(orderKey: 'k', order: order, select: (_) => true)
      ]);
      final entries = [
        for (var i = 0; i < 3; i++)
          QueueEntryRow(anchorRank: i, isGroup: false, mediaNodeId: order[i]),
      ];
      final overlay = SharedRowOverlay.fromPlan(
        baseCount: 3,
        entries: entries,
        groupsById: const {},
      );
      expect(overlay.absorbed.count, 0);
      expect(overlay.groupRows, isEmpty);
      expectRowsEqual(overlay.toEntries(base), entries);
    });
  });
}

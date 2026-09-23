import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/background_playback/model/domain/background_mapping.dart';
import 'package:iris/features/background_playback/model/domain/segment_edit_draft.dart';
import 'package:iris/features/background_playback/model/enum/mapping_action.dart';
import 'package:iris/features/background_playback/resolver/segment_span_math.dart';

void main() {
  group('SegmentEditDraft.toSegment', () {
    test('playMedia persists a strict 1:1 window', () {
      const draft = SegmentEditDraft(
        action: MappingAction.playMedia,
        span: SegmentSpan(fgStartMs: 10000, fgEndMs: 40000, bgOffsetMs: -5000),
        bgStorageId: 'local',
        bgPath: 'B.mp4',
      );
      final seg = draft.toSegment(fgTotalMs: 100000, bgTotalMs: 80000);
      expect(seg.adjustedRate, 1.0);
      expect(seg.bgStartMs, 5000);
      expect(seg.bgEndMs, 35000);
      expect(seg.bgEndMs! - seg.bgStartMs!, seg.fgEndMs - seg.fgStartMs);
      expect(seg.fgStartN, 0.1);
      expect(seg.bgEndN, 35000 / 80000);
    });

    test('silence carries no bg identity or rate', () {
      const draft = SegmentEditDraft(
        action: MappingAction.silence,
        span: SegmentSpan(fgStartMs: 0, fgEndMs: 5000),
      );
      final seg = draft.toSegment(fgTotalMs: 10000);
      expect(seg.isPlayMedia, isFalse);
      expect(seg.bgStorageId, isNull);
      expect(seg.bgPath, isNull);
      expect(seg.bgStartMs, isNull);
      expect(seg.adjustedRate, isNull);
    });
  });

  group('SegmentEditDraft.fromSegment', () {
    test('reconstructs the offset from the stored pair', () {
      final seg = MappingSegment(
        id: 7,
        action: MappingAction.playMedia,
        fgStartMs: 20000,
        fgEndMs: 50000,
        bgStorageId: 'local',
        bgPath: 'B.mp4',
        bgStartMs: 30000,
        bgEndMs: 60000,
      );
      final draft = SegmentEditDraft.fromSegment(seg);
      expect(draft.editingId, 7);
      expect(draft.span.fgStartMs, 20000);
      expect(draft.span.fgEndMs, 50000);
      expect(draft.span.bgOffsetMs, 10000);
      // Round-trips back to the same bg window.
      final back = draft.toSegment(fgTotalMs: 100000, bgTotalMs: 100000);
      expect(back.bgStartMs, seg.bgStartMs);
      expect(back.bgEndMs, seg.bgEndMs);
    });
  });
}

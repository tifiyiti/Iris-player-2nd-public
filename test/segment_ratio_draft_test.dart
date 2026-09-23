import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/background_playback/model/domain/background_mapping.dart';
import 'package:iris/features/background_playback/model/domain/segment_edit_draft.dart';
import 'package:iris/features/background_playback/model/enum/mapping_action.dart';
import 'package:iris/features/background_playback/resolver/segment_span_math.dart';

/// The per-segment volume split lives on the DRAFT (and then the saved
/// segment) — not on a store-wide "last used" value — so a fresh segment starts
/// at the 30/100 default and an existing one round-trips its own share.
void main() {
  MappingSegment playMedia({int? fg, int? bg}) => MappingSegment(
        action: MappingAction.playMedia,
        fgStartMs: 0,
        fgEndMs: 1000,
        bgStorageId: 's1',
        bgPath: 'a/b.mp4',
        bgStartMs: 0,
        bgEndMs: 1000,
        fgPercent: fg,
        bgPercent: bg,
      );

  test('fromSegment reads the segment share; toSegment writes it back', () {
    final draft = SegmentEditDraft.fromSegment(playMedia(fg: 55, bg: 0));
    expect(draft.fgPercent, 55);
    expect(draft.bgPercent, 0);

    final back = draft.toSegment(fgTotalMs: 1000, bgTotalMs: 1000);
    expect(back.fgPercent, 55);
    expect(back.bgPercent, 0);
  });

  test('a segment without a stored share falls back to the 30/100 default', () {
    final draft = SegmentEditDraft.fromSegment(playMedia());
    expect(draft.fgPercent, kDefaultSegmentFgPercent);
    expect(draft.bgPercent, kDefaultSegmentBgPercent);
  });

  test('a new draft defaults to 30/100 and persists that', () {
    const draft = SegmentEditDraft(
      action: MappingAction.playMedia,
      span: SegmentSpan(fgStartMs: 0, fgEndMs: 1000),
    );
    expect(draft.fgPercent, 30);
    expect(draft.bgPercent, 100);
    final seg = draft.toSegment(fgTotalMs: 1000, bgTotalMs: 1000);
    expect(seg.fgPercent, 30);
    expect(seg.bgPercent, 100);
  });

  test('copyWith updates one side without touching the other', () {
    const draft = SegmentEditDraft(
      action: MappingAction.playMedia,
      span: SegmentSpan(fgStartMs: 0, fgEndMs: 1000),
    );
    final edited = draft.copyWith(fgPercent: 10);
    expect(edited.fgPercent, 10);
    expect(edited.bgPercent, 100);
  });

  test('a silence segment carries no ratio at all', () {
    const draft = SegmentEditDraft(
      action: MappingAction.silence,
      span: SegmentSpan(fgStartMs: 0, fgEndMs: 1000),
    );
    final seg = draft.toSegment(fgTotalMs: 1000, bgTotalMs: 1000);
    expect(seg.fgPercent, isNull);
    expect(seg.bgPercent, isNull);
  });
}

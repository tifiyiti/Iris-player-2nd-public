import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/background_playback/model/domain/background_mapping.dart';
import 'package:iris/features/background_playback/model/enum/mapping_action.dart';
import 'package:iris/features/background_playback/resolver/active_mapping_resolver.dart';
import 'package:iris/features/background_playback/resolver/mapping_overview_math.dart';

/// v34 activation contract: only ACTIVE segments resolve, and where they
/// overlap the LARGEST `activeSeq` wins (last-activated-wins). Disabled
/// segments keep their data but never surface — not in playback, not on the
/// overview axis.
void main() {
  MappingSegment play(
    int start,
    int end, {
    int id = 0,
    int activeSeq = 1,
    bool isActive = true,
    String bg = 'B-side.mp4',
  }) =>
      MappingSegment(
        id: id,
        action: MappingAction.playMedia,
        fgStartMs: start,
        fgEndMs: end,
        bgStorageId: 'local',
        bgPath: bg,
        bgStartMs: 0,
        bgEndMs: end - start,
        bgStartN: 0,
        bgEndN: 1,
        isActive: isActive,
        activeSeq: activeSeq,
      );

  MappingSegment silence(
    int start,
    int end, {
    int activeSeq = 1,
    bool isActive = true,
  }) =>
      MappingSegment(
        action: MappingAction.silence,
        fgStartMs: start,
        fgEndMs: end,
        isActive: isActive,
        activeSeq: activeSeq,
      );

  group('effectiveAt', () {
    test('returns null in a gap', () {
      expect(ActiveMappingResolver.effectiveAt([play(1000, 3000)], 500), isNull);
    });

    test('a disabled segment is invisible', () {
      final segs = [play(0, 10000, isActive: false)];
      expect(ActiveMappingResolver.effectiveAt(segs, 1000), isNull);
    });

    test('the later-activated segment wins the overlap', () {
      final early = play(0, 10000, id: 1, activeSeq: 1, bg: 'early.mp4');
      final late = play(5000, 15000, id: 2, activeSeq: 2, bg: 'late.mp4');
      final segs = [early, late];

      expect(ActiveMappingResolver.effectiveAt(segs, 2000)?.bgPath, 'early.mp4');
      expect(ActiveMappingResolver.effectiveAt(segs, 7000)?.bgPath, 'late.mp4');
      expect(ActiveMappingResolver.effectiveAt(segs, 12000)?.bgPath, 'late.mp4');
    });

    test('deactivating the later segment re-exposes the earlier one', () {
      final early = play(0, 10000, id: 1, activeSeq: 1, bg: 'early.mp4');
      final late = play(
        5000,
        15000,
        id: 2,
        activeSeq: 2,
        bg: 'late.mp4',
        isActive: false,
      );
      expect(
        ActiveMappingResolver.effectiveAt([early, late], 7000)?.bgPath,
        'early.mp4',
      );
    });

    test('range is half-open at both ends', () {
      final segs = [play(1000, 3000)];
      expect(ActiveMappingResolver.effectiveAt(segs, 1000), isNotNull);
      expect(ActiveMappingResolver.effectiveAt(segs, 2999), isNotNull);
      expect(ActiveMappingResolver.effectiveAt(segs, 3000), isNull);
    });

    test('zero sequences fall back to the later fg start', () {
      final a = play(0, 10000, id: 1, activeSeq: 0, bg: 'a.mp4');
      final b = play(5000, 15000, id: 2, activeSeq: 0, bg: 'b.mp4');
      expect(ActiveMappingResolver.effectiveAt([a, b], 7000)?.bgPath, 'b.mp4');
    });
  });

  group('nextActiveSeq', () {
    test('is one past the maximum, at least 1', () {
      expect(ActiveMappingResolver.nextActiveSeq(const []), 1);
      expect(
        ActiveMappingResolver.nextActiveSeq([play(0, 1, activeSeq: 0)]),
        1,
      );
      expect(
        ActiveMappingResolver.nextActiveSeq([
          play(0, 1, activeSeq: 3),
          play(2, 3, activeSeq: 7),
        ]),
        8,
      );
    });
  });

  group('visibleBlocks', () {
    const total = 100000;

    test('an inactive-only timeline is one full gap', () {
      final blocks = ActiveMappingResolver.visibleBlocks(
        segments: [play(1000, 3000, isActive: false)],
        fgTotalMs: total,
      );
      expect(blocks, hasLength(1));
      expect(blocks.single.kind, MappingBlockKind.gap);
      expect(blocks.single.startMs, 0);
      expect(blocks.single.endMs, total);
    });

    test('the shadowed segment never reaches the axis', () {
      final early = play(0, 10000, id: 1, activeSeq: 1, bg: 'early.mp4');
      final late = play(5000, 15000, id: 2, activeSeq: 2, bg: 'late.mp4');
      final blocks = ActiveMappingResolver.visibleBlocks(
        segments: [early, late],
        fgTotalMs: total,
      );
      // 0..5000 early, 5000..15000 late, 15000..total gap.
      expect(blocks.map((b) => b.kind), [
        MappingBlockKind.covered,
        MappingBlockKind.covered,
        MappingBlockKind.gap,
      ]);
      expect(blocks[0].segment?.bgPath, 'early.mp4');
      expect(blocks[1].segment?.bgPath, 'late.mp4');
      expect(blocks[1].startMs, 5000);
      expect(blocks[1].endMs, 15000);
    });

    test('the late winner splits an earlier window into one continuous slice',
        () {
      // early covers 0..30000; late claims 10000..20000. The early slice must
      // come back as two colour runs with the SAME segment, never re-split by
      // the late edges into duplicate blocks.
      final early = play(0, 30000, id: 1, activeSeq: 1, bg: 'early.mp4');
      final late = play(10000, 20000, id: 2, activeSeq: 2, bg: 'late.mp4');
      final blocks = ActiveMappingResolver.visibleBlocks(
        segments: [early, late],
        fgTotalMs: total,
      );
      expect(blocks.map((b) => b.kind), [
        MappingBlockKind.covered,
        MappingBlockKind.covered,
        MappingBlockKind.covered,
        MappingBlockKind.gap,
      ]);
      expect(blocks[0].segment?.bgPath, 'early.mp4');
      expect(blocks[1].segment?.bgPath, 'late.mp4');
      expect(blocks[2].segment?.bgPath, 'early.mp4');
      // Contiguous runs of one file merge into a single block.
      expect(blocks[0].startMs, 0);
      expect(blocks[0].endMs, 10000);
      expect(blocks[2].startMs, 20000);
      expect(blocks[2].endMs, 30000);
    });

    test('a silence winner paints a silence block', () {
      final segs = [silence(1000, 2000)];
      final blocks = ActiveMappingResolver.visibleBlocks(
        segments: segs,
        fgTotalMs: total,
      );
      expect(blocks.map((b) => b.kind), [
        MappingBlockKind.gap,
        MappingBlockKind.silence,
        MappingBlockKind.gap,
      ]);
    });

    test('a background shorter than the window yields an uncovered tail', () {
      // bg window 0..10000 over a 20000 fg span → 10000..20000 uncovered.
      final seg = MappingSegment(
        action: MappingAction.playMedia,
        fgStartMs: 0,
        fgEndMs: 20000,
        bgStorageId: 'local',
        bgPath: 'short.mp4',
        bgStartMs: 0,
        bgEndMs: 10000,
        bgStartN: 0,
        bgEndN: 1,
        activeSeq: 1,
      );
      final blocks = ActiveMappingResolver.visibleBlocks(
        segments: [seg],
        fgTotalMs: total,
      );
      expect(blocks.map((b) => b.kind), [
        MappingBlockKind.covered,
        MappingBlockKind.uncovered,
        MappingBlockKind.gap,
      ]);
    });
  });

  group('segmentKey', () {
    test('distinguishes same-span winners by sequence and bg', () {
      final a = play(0, 10000, id: 1, activeSeq: 1, bg: 'a.mp4');
      final b = play(0, 10000, id: 2, activeSeq: 2, bg: 'b.mp4');
      expect(ActiveMappingResolver.segmentKey(a),
          isNot(ActiveMappingResolver.segmentKey(b)));
    });
  });

  group('mergeSegment', () {
    test('overwrite replaces the edited row in place and keeps the rest', () {
      final a = play(0, 10000, id: 1, activeSeq: 1, bg: 'a.mp4');
      final b = play(20000, 30000, id: 2, activeSeq: 2, bg: 'b.mp4');
      final edited = play(1000, 5000, id: 1, activeSeq: 1, bg: 'a2.mp4');

      final merged = ActiveMappingResolver.mergeSegment(
        all: [a, b],
        next: edited,
        asNew: false,
        editingId: 1,
      );
      expect(merged, hasLength(2));
      expect(merged.map((s) => s.id), [1, 2]);
      // The edited row's new content landed under the SAME id/sequence.
      final row = merged.firstWhere((s) => s.id == 1);
      expect(row.bgPath, 'a2.mp4');
      expect(row.activeSeq, 1);
    });

    test('save-as-new appends and keeps the shadowed row', () {
      final a = play(0, 10000, id: 1, activeSeq: 1, bg: 'a.mp4');
      final fresh = play(1000, 5000, id: 0, activeSeq: 2, bg: 'new.mp4');

      final merged = ActiveMappingResolver.mergeSegment(
        all: [a],
        next: fresh,
        asNew: true,
        editingId: 1,
      );
      expect(merged, hasLength(2));
      expect(merged.map((s) => s.bgPath), ['a.mp4', 'new.mp4']);
    });

    test('a new draft (id 0) always appends', () {
      final a = play(0, 10000, id: 1, activeSeq: 3, bg: 'a.mp4');
      final fresh = play(2000, 4000, id: 0, activeSeq: 4, bg: 'new.mp4');

      final merged = ActiveMappingResolver.mergeSegment(
        all: [a],
        next: fresh,
        asNew: false,
        editingId: 0,
      );
      expect(merged, hasLength(2));
    });

    test('output is sorted by foreground start', () {
      final a = play(20000, 30000, id: 1, activeSeq: 1, bg: 'a.mp4');
      final fresh = play(1000, 5000, id: 0, activeSeq: 2, bg: 'new.mp4');

      final merged = ActiveMappingResolver.mergeSegment(
        all: [a],
        next: fresh,
        asNew: true,
        editingId: 1,
      );
      expect(merged.map((s) => s.fgStartMs), [1000, 20000]);
    });
  });
}

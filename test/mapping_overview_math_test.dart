import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/background_playback/model/domain/background_mapping.dart';
import 'package:iris/features/background_playback/model/enum/mapping_action.dart';
import 'package:iris/features/background_playback/resolver/mapping_overview_math.dart';

void main() {
  MappingSegment play(
    int start,
    int end, {
    int bgStart = 0,
    int bgEnd = 30000,
    double? bgStartN,
    double? bgEndN,
  }) =>
      MappingSegment(
        action: MappingAction.playMedia,
        fgStartMs: start,
        fgEndMs: end,
        bgStorageId: 'local',
        bgPath: 'Anime/B-side.mp4',
        bgStartMs: bgStart,
        bgEndMs: bgEnd,
        bgStartN: bgStartN,
        bgEndN: bgEndN,
      );

  const total = 100000;

  test('no segments yields one full-width gap', () {
    final blocks =
        MappingOverviewMath.layout(segments: const [], fgTotalMs: total);
    expect(blocks, hasLength(1));
    expect(blocks.single.kind, MappingBlockKind.gap);
    expect(blocks.single.startMs, 0);
    expect(blocks.single.endMs, total);
  });

  test('a covered playMedia segment splits into gap/covered/gap', () {
    final blocks = MappingOverviewMath.layout(
      segments: [
        // off = bgStart - fgStart = -10000; total = 30000/1.0 = 30000,
        // coverage = [10000, 40000] == the whole window.
        play(10000, 40000,
            bgStart: 0, bgEnd: 30000, bgStartN: 0, bgEndN: 1.0),
      ],
      fgTotalMs: total,
    );
    expect(blocks.map((b) => b.kind), [
      MappingBlockKind.gap,
      MappingBlockKind.covered,
      MappingBlockKind.gap,
    ]);
    expect(blocks[0].startMs, 0);
    expect(blocks[0].endMs, 10000);
    expect(blocks[1].startMs, 10000);
    expect(blocks[1].endMs, 40000);
    expect(blocks[2].startMs, 40000);
    expect(blocks[2].endMs, total);
  });

  test('a window longer than its file yields a gray uncovered tail', () {
    // bgEndN = 30000/20000 = 1.5 → recovered total 20000, off = -10000,
    // coverage = [10000, 30000], so 30000..40000 is uncovered.
    final blocks = MappingOverviewMath.layout(
      segments: [
        play(10000, 40000,
            bgStart: 0, bgEnd: 30000, bgStartN: 0, bgEndN: 1.5),
      ],
      fgTotalMs: total,
    );
    final kinds = blocks.map((b) => b.kind).toList();
    expect(kinds, [
      MappingBlockKind.gap,
      MappingBlockKind.covered,
      MappingBlockKind.uncovered,
      MappingBlockKind.gap,
    ]);
    expect(blocks[2].startMs, 30000);
    expect(blocks[2].endMs, 40000);
  });

  test('silence segments are their own block kind', () {
    final blocks = MappingOverviewMath.layout(
      segments: const [
        MappingSegment(
          action: MappingAction.silence,
          fgStartMs: 20000,
          fgEndMs: 50000,
        ),
      ],
      fgTotalMs: total,
    );
    expect(blocks.map((b) => b.kind), [
      MappingBlockKind.gap,
      MappingBlockKind.silence,
      MappingBlockKind.gap,
    ]);
  });

  test('without recoverable norms the whole window counts as covered', () {
    final blocks = MappingOverviewMath.layout(
      segments: [play(10000, 40000)],
      fgTotalMs: total,
    );
    expect(blocks.map((b) => b.kind), [
      MappingBlockKind.gap,
      MappingBlockKind.covered,
      MappingBlockKind.gap,
    ]);
  });

  test('fracOf maps ms to a clamped 0..1 fraction', () {
    expect(MappingOverviewMath.fracOf(0, total), 0);
    expect(MappingOverviewMath.fracOf(50000, total), 0.5);
    expect(MappingOverviewMath.fracOf(200000, total), 1);
    expect(MappingOverviewMath.fracOf(10, 0), isNull);
  });
}

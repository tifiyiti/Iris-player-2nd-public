import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/background_playback/model/domain/background_mapping.dart';
import 'package:iris/features/background_playback/model/enum/mapping_action.dart';
import 'package:iris/features/background_playback/resolver/mapping_overlap.dart';

/// B3 regression: keepFront/keepBack must clip the bg window 1:1 with the fg
/// window, mirroring `splitAroundExisting._residual`. Clipping only fg breaks
/// the 1:1 invariant (`SegmentEditDraft.toSegment` writes 1:1) and the stored
/// segment silently plays back at a scaled rate.
MappingSegment play(int fgS, int fgE, {int? bgS, int? bgE}) =>
    MappingSegment(
      action: MappingAction.playMedia,
      fgStartMs: fgS,
      fgEndMs: fgE,
      bgStorageId: 'local',
      bgPath: 'B.mp4',
      bgStartMs: bgS ?? fgS,
      bgEndMs: bgE ?? fgE,
    );

MappingSegment silence(int s, int e) => MappingSegment(
      action: MappingAction.silence,
      fgStartMs: s,
      fgEndMs: e,
    );

void main() {
  group('MappingOverlap keepFront/keepBack bg window 1:1', () {
    test('keepFront preserves the 1:1 offset (zero offset)', () {
      final out = MappingOverlap.resolve(
        existing: [play(30000, 60000)],
        next: play(10000, 70000),
        choice: OverlapChoice.keepFront,
      )!;
      final kept = out.firstWhere((s) => s.fgStartMs == 10000);
      expect(kept.fgEndMs, 30000);
      expect(kept.bgStartMs, 10000);
      expect(kept.bgEndMs, 30000);
    });

    test('keepBack preserves the 1:1 offset (zero offset)', () {
      final out = MappingOverlap.resolve(
        existing: [play(30000, 60000)],
        next: play(10000, 70000),
        choice: OverlapChoice.keepBack,
      )!;
      final kept = out.firstWhere((s) => s.fgStartMs == 60000);
      expect(kept.fgEndMs, 70000);
      expect(kept.bgStartMs, 60000);
      expect(kept.bgEndMs, 70000);
    });

    test('keepFront shifts a non-zero offset window by the same delta', () {
      // Draft fg 10000-70000 maps to bg 5000-65000 (offset -5000).
      final out = MappingOverlap.resolve(
        existing: [play(30000, 60000)],
        next: play(10000, 70000, bgS: 5000, bgE: 65000),
        choice: OverlapChoice.keepFront,
      )!;
      final kept = out.firstWhere((s) => s.fgStartMs == 10000);
      expect(kept.fgEndMs, 30000);
      expect(kept.bgStartMs, 5000);
      expect(kept.bgEndMs, 25000);
    });

    test('keepBack shifts a non-zero offset window by the same delta', () {
      final out = MappingOverlap.resolve(
        existing: [play(30000, 60000)],
        next: play(10000, 70000, bgS: 5000, bgE: 65000),
        choice: OverlapChoice.keepBack,
      )!;
      final kept = out.firstWhere((s) => s.fgStartMs == 60000);
      expect(kept.fgEndMs, 70000);
      expect(kept.bgStartMs, 55000);
      expect(kept.bgEndMs, 65000);
    });

    test('keepFront on a silence draft keeps null bg windows', () {
      final out = MappingOverlap.resolve(
        existing: [play(30000, 60000)],
        next: silence(10000, 70000),
        choice: OverlapChoice.keepFront,
      )!;
      final kept = out.firstWhere((s) => s.fgStartMs == 10000);
      expect(kept.fgEndMs, 30000);
      expect(kept.bgStartMs, isNull);
      expect(kept.bgEndMs, isNull);
    });
  });
}

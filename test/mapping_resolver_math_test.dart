import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/background_playback/model/domain/background_mapping.dart';
import 'package:iris/features/background_playback/model/enum/mapping_action.dart';
import 'package:iris/features/background_playback/resolver/mapping_overlap.dart';
import 'package:iris/features/background_playback/resolver/mapping_timeline_math.dart';

MappingSegment play(int s, int e) => MappingSegment(
      action: MappingAction.playMedia,
      fgStartMs: s,
      fgEndMs: e,
      bgStorageId: 'local',
      bgPath: 'B.mp4',
      bgStartMs: s ~/ 2,
      bgEndMs: e ~/ 2,
    );

MappingSegment silence(int s, int e) => MappingSegment(
      action: MappingAction.silence,
      fgStartMs: s,
      fgEndMs: e,
    );

void main() {
  group('MappingTimelineMath', () {
    test('segmentAt resolves the covering window (half-open), else gap', () {
      final segs = [play(1000, 3000), silence(5000, 6000)];
      expect(MappingTimelineMath.segmentAt(segs, 0), isNull);
      expect(MappingTimelineMath.segmentAt(segs, 1000)!.action,
          MappingAction.playMedia);
      expect(MappingTimelineMath.segmentAt(segs, 2999), isNotNull);
      expect(MappingTimelineMath.segmentAt(segs, 3000), isNull);
      expect(MappingTimelineMath.segmentAt(segs, 5500)!.action,
          MappingAction.silence);
    });

    test('proportional bg target inside a playMedia window', () {
      // fg 0..2000 → bg 1000..3000 (1:1): fg 500 ⇒ bg 1500.
      final s = MappingSegment(
        action: MappingAction.playMedia,
        fgStartMs: 0,
        fgEndMs: 2000,
        bgStorageId: 's',
        bgPath: 'b',
        bgStartMs: 1000,
        bgEndMs: 3000,
      );
      expect(MappingTimelineMath.bgTargetMsFor(s, 0), 1000);
      expect(MappingTimelineMath.bgTargetMsFor(s, 500), 1500);
      expect(MappingTimelineMath.bgTargetMsFor(s, 2000), 3000);
    });

    test('segment rate spans the B window across the A window (clamped)', () {
      // A 0..2000, B 0..1000 → 0.5x of fgRate.
      final s = MappingSegment(
        action: MappingAction.playMedia,
        fgStartMs: 0,
        fgEndMs: 2000,
        bgStorageId: 's',
        bgPath: 'b',
        bgStartMs: 0,
        bgEndMs: 1000,
      );
      expect(MappingTimelineMath.segmentRate(s, 1.0), 0.5);
      // A 0..1000, B 0..4000 → would be 4.0 → clamped to 2.0 + flagged.
      final wide = MappingSegment(
        action: MappingAction.playMedia,
        fgStartMs: 0,
        fgEndMs: 1000,
        bgStorageId: 's',
        bgPath: 'b',
        bgStartMs: 0,
        bgEndMs: 4000,
      );
      expect(MappingTimelineMath.segmentRate(wide, 1.0), 2.0);
      expect(MappingTimelineMath.rateOutOfRange(wide, 1.0), isTrue);
    });

    test('normalized fractions derive from total durations', () {
      expect(MappingTimelineMath.normOf(3000, 6000), 0.5);
      expect(MappingTimelineMath.normOf(3000, null), isNull);
    });
  });

  group('MappingOverlap', () {
    test('no overlap inserts plainly', () {
      final out = MappingOverlap.resolve(
        existing: [play(0, 1000)],
        next: silence(2000, 3000),
        choice: OverlapChoice.overwrite,
      );
      expect(out, hasLength(2));
    });

    test('keepFront clips the new segment before the existing one', () {
      final existing = [play(30000, 60000)];
      final next = play(10000, 70000);
      final out = MappingOverlap.resolve(
          existing: existing, next: next, choice: OverlapChoice.keepFront)!;
      expect(out, hasLength(2));
      final kept = out.firstWhere((s) => s.fgStartMs == 10000);
      expect(kept.fgEndMs, 30000);
    });

    test('keepBack clips the new segment after the existing one', () {
      final existing = [play(30000, 60000)];
      final next = play(10000, 70000);
      final out = MappingOverlap.resolve(
          existing: existing, next: next, choice: OverlapChoice.keepBack)!;
      final kept = out.firstWhere((s) => s.fgStartMs == 60000);
      expect(kept.fgEndMs, 70000);
    });

    test('overwrite drops the covered old segment', () {
      final existing = [play(30000, 60000), silence(70000, 80000)];
      final next = play(10000, 70000);
      final out = MappingOverlap.resolve(
          existing: existing, next: next, choice: OverlapChoice.overwrite)!;
      expect(out, hasLength(2)); // full new + untouched silence
      expect(out.first.fgStartMs, 10000);
      expect(out.first.fgEndMs, 70000);
      expect(out.any((s) => s.action == MappingAction.silence), isTrue);
    });

    test('keepFront with no free space before returns null', () {
      final existing = [play(0, 60000)];
      final next = play(10000, 70000);
      final out = MappingOverlap.resolve(
          existing: existing, next: next, choice: OverlapChoice.keepFront);
      expect(out, isNull);
    });
  });
}

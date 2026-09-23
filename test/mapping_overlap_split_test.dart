import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/background_playback/model/domain/background_mapping.dart';
import 'package:iris/features/background_playback/model/enum/mapping_action.dart';
import 'package:iris/features/background_playback/resolver/mapping_overlap.dart';

/// A playMedia segment with a 1:1 offset of 0 (bgStart == fgStart) so residual
/// assertions can check the bg window shift directly.
MappingSegment play(int s, int e) => MappingSegment(
      action: MappingAction.playMedia,
      fgStartMs: s,
      fgEndMs: e,
      bgStorageId: 'local',
      bgPath: 'B.mp4',
      bgStartMs: s,
      bgEndMs: e,
    );

void main() {
  group('MappingOverlap.splitAroundExisting', () {
    test('no overlap returns the draft unchanged', () {
      final out = MappingOverlap.splitAroundExisting(
        existing: [play(0, 10000)],
        next: play(20000, 30000),
      );
      expect(out, hasLength(1));
      expect(out.single.fgStartMs, 20000);
      expect(out.single.fgEndMs, 30000);
    });

    test('middle overlap yields a left and a right residual', () {
      final out = MappingOverlap.splitAroundExisting(
        existing: [play(30000, 60000)],
        next: play(10000, 70000),
      );
      expect(out, hasLength(2));
      final left = out.firstWhere((s) => s.fgStartMs == 10000);
      final right = out.firstWhere((s) => s.fgEndMs == 70000);
      expect(left.fgEndMs, 30000);
      expect(right.fgStartMs, 60000);
      // 1:1 offset preserved on both residuals.
      expect(left.bgStartMs, 10000);
      expect(left.bgEndMs, 30000);
      expect(right.bgStartMs, 60000);
      expect(right.bgEndMs, 70000);
    });

    test('head overlap yields only the right residual', () {
      final out = MappingOverlap.splitAroundExisting(
        existing: [play(0, 30000)],
        next: play(10000, 70000),
      );
      expect(out, hasLength(1));
      expect(out.single.fgStartMs, 30000);
      expect(out.single.fgEndMs, 70000);
      expect(out.single.bgStartMs, 30000);
    });

    test('fully covered draft yields nothing', () {
      final out = MappingOverlap.splitAroundExisting(
        existing: [play(0, 100000)],
        next: play(10000, 70000),
      );
      expect(out, isEmpty);
    });

    test('straddling two existing segments yields three residuals', () {
      // Existing blocks 20000..30000 and 40000..50000; the draft spans both,
      // so it survives as three free gaps.
      final out = MappingOverlap.splitAroundExisting(
        existing: [play(20000, 30000), play(40000, 50000)],
        next: play(10000, 60000),
      );
      expect(out, hasLength(3));
      expect(out.map((s) => '${s.fgStartMs}-${s.fgEndMs}'),
          ['10000-20000', '30000-40000', '50000-60000']);
    });
  });
}

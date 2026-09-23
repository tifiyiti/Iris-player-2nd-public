import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/background_playback/resolver/vm_tiled_plan.dart';

/// One-shot loop tiling of the bg queue across a virtual-merged video.
///
/// The bg queue is treated as one continuous timeline (files concatenated in
/// order, looping) laid over the virtual total; each VM segment entrance maps
/// to the bg file + inner offset under its start (see plan v3).
void main() {
  group('resolveVmTiledBgPlan', () {
    test('equal lengths map head-to-head', () {
      final plan = resolveVmTiledBgPlan(
        segmentDurationsMs: const [10000, 10000],
        bgDurationsMs: const [10000, 10000],
      );
      expect(plan, const [
        VmTiledSlot(bgIndex: 0, bgOffsetMs: 0),
        VmTiledSlot(bgIndex: 1, bgOffsetMs: 0),
      ]);
    });

    test('a segment starting mid-file keeps the inner offset', () {
      final plan = resolveVmTiledBgPlan(
        segmentDurationsMs: const [5000, 5000, 5000],
        bgDurationsMs: const [10000, 5000],
      );
      expect(plan, const [
        VmTiledSlot(bgIndex: 0, bgOffsetMs: 0),
        VmTiledSlot(bgIndex: 0, bgOffsetMs: 5000),
        VmTiledSlot(bgIndex: 1, bgOffsetMs: 0),
      ]);
    });

    test('a single bg file wraps inside itself', () {
      final plan = resolveVmTiledBgPlan(
        segmentDurationsMs: const [8000, 8000],
        bgDurationsMs: const [10000],
      );
      expect(plan, const [
        VmTiledSlot(bgIndex: 0, bgOffsetMs: 0),
        VmTiledSlot(bgIndex: 0, bgOffsetMs: 8000),
      ]);
    });

    test('startBgIndex moves the tiling origin', () {
      final plan = resolveVmTiledBgPlan(
        segmentDurationsMs: const [3000, 3000],
        bgDurationsMs: const [4000, 4000],
        startBgIndex: 1,
      );
      expect(plan, const [
        VmTiledSlot(bgIndex: 1, bgOffsetMs: 0),
        VmTiledSlot(bgIndex: 1, bgOffsetMs: 3000),
      ]);
    });

    test('zero-duration bg entries are skipped', () {
      final plan = resolveVmTiledBgPlan(
        segmentDurationsMs: const [2000, 2000],
        bgDurationsMs: const [0, 5000],
      );
      expect(plan, const [
        VmTiledSlot(bgIndex: 1, bgOffsetMs: 0),
        VmTiledSlot(bgIndex: 1, bgOffsetMs: 2000),
      ]);
    });

    test('an out-of-range startBgIndex clamps into range', () {
      final plan = resolveVmTiledBgPlan(
        segmentDurationsMs: const [1000],
        bgDurationsMs: const [5000, 5000],
        startBgIndex: 99,
      );
      expect(plan, const [VmTiledSlot(bgIndex: 0, bgOffsetMs: 0)]);
    });

    test('zero-length segments hold a null slot and do not advance', () {
      final plan = resolveVmTiledBgPlan(
        segmentDurationsMs: const [4000, 0, 4000],
        bgDurationsMs: const [8000],
      );
      expect(plan[0], const VmTiledSlot(bgIndex: 0, bgOffsetMs: 0));
      expect(plan[1], isNull);
      expect(plan[2], const VmTiledSlot(bgIndex: 0, bgOffsetMs: 4000));
    });

    test('an unusable bg timeline degrades to all-null (keep playing)', () {
      expect(
        resolveVmTiledBgPlan(
          segmentDurationsMs: const [4000, 4000],
          bgDurationsMs: const [0, 0],
        ),
        const [null, null],
      );
      expect(
        resolveVmTiledBgPlan(
          segmentDurationsMs: const [4000],
          bgDurationsMs: const <int>[],
        ),
        const [null],
      );
      expect(
        resolveVmTiledBgPlan(
          segmentDurationsMs: const <int>[],
          bgDurationsMs: const [5000],
        ),
        isEmpty,
      );
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/virtual_media/playback/vm_playback_controller.dart';

/// Boundary semantics of stepping within/across virtual items (spec §9.4,
/// album/track model).
void main() {
  // Session: 2 items, 3 segments each.
  const q = 2, seg = 3;

  int? qOf(VmAdvancePlan? p) => p?.queueIndex;
  int? sOf(VmAdvancePlan? p) => p?.segmentIndex;

  test('within item: forward/backward move segments', () {
    final fwd = vmPlanAdvance(
        queueIndex: 0, segmentIndex: 0,
        queueLength: q, segmentsLength: seg, forward: true);
    expect(qOf(fwd), 0);
    expect(sOf(fwd), 1);

    final back = vmPlanAdvance(
        queueIndex: 1, segmentIndex: 2,
        queueLength: q, segmentsLength: seg, forward: false);
    expect(qOf(back), 1);
    expect(sOf(back), 1);
  });

  test('forward at last segment crosses into next item at its start', () {
    final p = vmPlanAdvance(
        queueIndex: 0, segmentIndex: seg - 1,
        queueLength: q, segmentsLength: seg, forward: true);
    expect(qOf(p), 1);
    expect(sOf(p), 0);
    expect(p!.atItemEnd, isFalse);
  });

  test('backward at first segment enters previous item at its LAST segment',
      () {
    final p = vmPlanAdvance(
        queueIndex: 1, segmentIndex: 0,
        queueLength: q, segmentsLength: seg, forward: false);
    expect(qOf(p), 0);
    expect(sOf(p), 0); // planner signals via atItemEnd
    expect(p!.atItemEnd, isTrue);
  });

  test('forward past the end ends the session without wrap', () {
    final p = vmPlanAdvance(
        queueIndex: q - 1, segmentIndex: seg - 1,
        queueLength: q, segmentsLength: seg, forward: true);
    expect(p!.ended, isTrue);
  });

  test('backward before the start ends the session without wrap', () {
    final p = vmPlanAdvance(
        queueIndex: 0, segmentIndex: 0,
        queueLength: q, segmentsLength: seg, forward: false);
    expect(p!.ended, isTrue);
  });

  test('wrap under Repeat.all cycles both directions', () {
    final wrapFwd = vmPlanAdvance(
        queueIndex: q - 1, segmentIndex: seg - 1,
        queueLength: q, segmentsLength: seg,
        forward: true, wrapRepeatAll: true);
    expect(qOf(wrapFwd), 0);
    expect(sOf(wrapFwd), 0);

    final wrapBack = vmPlanAdvance(
        queueIndex: 0, segmentIndex: 0,
        queueLength: q, segmentsLength: seg,
        forward: false, wrapRepeatAll: true);
    expect(qOf(wrapBack), q - 1);
    expect(sOf(wrapBack), 0);
    expect(wrapBack!.atItemEnd, isTrue);
  });

  group('vmPlanFeasibleAdvance (H1: never plan onto an unplayable item)', () {
    bool Function(int) feasible(Set<int> ok) => (int i) => ok.contains(i);

    test('same-item segment step is kept (the playing item is feasible)', () {
      final p = vmPlanFeasibleAdvance(
        queueIndex: 0,
        segmentIndex: 0,
        queueLength: 2,
        segmentsLength: seg,
        forward: true,
        isFeasible: feasible({0, 1}),
      );
      expect(qOf(p), 0);
      expect(sOf(p), 1);
    });

    test('forward cross-item skips an infeasible neighbour', () {
      // Item 1 is unplayable (empty / zero duration) → land on item 2.
      final p = vmPlanFeasibleAdvance(
        queueIndex: 0,
        segmentIndex: seg - 1,
        queueLength: 3,
        segmentsLength: seg,
        forward: true,
        isFeasible: feasible({0, 2}),
      );
      expect(qOf(p), 2);
      expect(sOf(p), 0);
      expect(p!.ended, isFalse);
    });

    test('backward cross-item skips siblings and lands on the tail', () {
      final p = vmPlanFeasibleAdvance(
        queueIndex: 2,
        segmentIndex: 0,
        queueLength: 3,
        segmentsLength: seg,
        forward: false,
        isFeasible: feasible({0, 2}),
      );
      expect(qOf(p), 0);
      expect(p!.atItemEnd, isTrue);
      expect(p.ended, isFalse);
    });

    test('no feasible neighbour ends the session instead of sticking', () {
      final p = vmPlanFeasibleAdvance(
        queueIndex: 0,
        segmentIndex: seg - 1,
        queueLength: 2,
        segmentsLength: seg,
        forward: true,
        isFeasible: feasible({0}),
      );
      expect(p!.ended, isTrue);
    });

    test('Repeat.all wrap still skips to a playable wrapped target', () {
      // Wrapped to item 0, which is unplayable → continue forward to item 1.
      final p = vmPlanFeasibleAdvance(
        queueIndex: 2,
        segmentIndex: seg - 1,
        queueLength: 3,
        segmentsLength: seg,
        forward: true,
        wrapRepeatAll: true,
        isFeasible: feasible({1, 2}),
      );
      expect(qOf(p), 1);
      expect(sOf(p), 0);
    });

    test('vmNearestFeasibleQueueIndex scans strictly in one direction', () {
      expect(
        vmNearestFeasibleQueueIndex(
          fromIndex: 1,
          queueLength: 4,
          forward: true,
          isFeasible: feasible({0, 3}),
        ),
        3,
      );
      expect(
        vmNearestFeasibleQueueIndex(
          fromIndex: 1,
          queueLength: 4,
          forward: false,
          isFeasible: feasible({0, 3}),
        ),
        0,
      );
      expect(
        vmNearestFeasibleQueueIndex(
          fromIndex: 3,
          queueLength: 4,
          forward: true,
          isFeasible: feasible({0, 3}),
        ),
        isNull,
      );
    });
  });

  group('vmPlanAdvance wrapWithinItem + vmRepeatOneHandlesWithinItem (H4)', () {
    test('advances within the item up to the last segment', () {
      final p = vmPlanAdvance(
        queueIndex: 0,
        segmentIndex: 0,
        queueLength: q,
        segmentsLength: seg,
        forward: true,
        wrapWithinItem: true,
      );
      expect(qOf(p), 0);
      expect(sOf(p), 1);
    });

    test('wraps to the item head after the last segment (no item crossing)', () {
      final p = vmPlanAdvance(
        queueIndex: 1,
        segmentIndex: seg - 1,
        queueLength: q,
        segmentsLength: seg,
        forward: true,
        wrapWithinItem: true,
      );
      expect(qOf(p), 1);
      expect(sOf(p), 0);
      expect(p!.ended, isFalse);
    });

    test('multi-segment items are handled by the controller, single are not',
        () {
      expect(
        vmRepeatOneHandlesWithinItem(segmentsLength: 3, segmentIndex: 2),
        isTrue,
      );
      expect(
        vmRepeatOneHandlesWithinItem(segmentsLength: 1, segmentIndex: 0),
        isFalse,
      );
    });
  });
}

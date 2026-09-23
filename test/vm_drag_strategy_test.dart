import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/virtual_media/interaction/state/vm_drag_gate.dart';
import 'package:iris/features/virtual_media/model/enum/vm_enums.dart';

void main() {
  group('decideVmDragSeek', () {
    test('taps always act immediately regardless of strategy', () {
      for (final s in VmCrossSegmentDragStrategy.values) {
        expect(
          decideVmDragSeek(
              strategy: s, isDragging: false, crossSegment: true),
          VmDragSeekDecision.seekNow,
        );
      }
    });

    test('same-segment drag ticks always seek live', () {
      for (final s in VmCrossSegmentDragStrategy.values) {
        expect(
          decideVmDragSeek(
              strategy: s, isDragging: true, crossSegment: false),
          VmDragSeekDecision.seekNow,
        );
      }
    });

    test('directSwitch drags jump immediately', () {
      expect(
        decideVmDragSeek(
          strategy: VmCrossSegmentDragStrategy.directSwitch,
          isDragging: true,
          crossSegment: true,
        ),
        VmDragSeekDecision.seekNow,
      );
    });

    test('previewOnRelease drags stash until release', () {
      expect(
        decideVmDragSeek(
          strategy: VmCrossSegmentDragStrategy.previewOnRelease,
          isDragging: true,
          crossSegment: true,
        ),
        VmDragSeekDecision.stashPreview,
      );
    });

    test('hidden clampToCurrent falls back to direct (never dead)', () {
      expect(
        decideVmDragSeek(
          strategy: VmCrossSegmentDragStrategy.clampToCurrent,
          isDragging: true,
          crossSegment: true,
        ),
        VmDragSeekDecision.seekNow,
      );
    });
  });

  group('vmCrossJumpAllowed (300ms open throttle)', () {    test('first jump of a drag always allowed', () {
      expect(vmCrossJumpAllowed(null, DateTime(2026, 1, 1)), isTrue);
    });

    test('ticks inside the window are throttled', () {
      final t0 = DateTime(2026, 1, 1);
      expect(
        vmCrossJumpAllowed(t0, t0.add(const Duration(milliseconds: 299))),
        isFalse,
      );
    });

    test('ticks past the window pass', () {
      final t0 = DateTime(2026, 1, 1);
      expect(
        vmCrossJumpAllowed(t0, t0.add(const Duration(milliseconds: 300))),
        isTrue,
      );
    });
  });

  group('vmCrossJumpStashes (release commit bypasses the live throttle)', () {
    test('live tick inside the throttle window is stashed', () {
      expect(
        vmCrossJumpStashes(dragging: true, withinThrottleWindow: true),
        isTrue,
      );
    });

    test('live tick outside the window opens immediately', () {
      expect(
        vmCrossJumpStashes(dragging: true, withinThrottleWindow: false),
        isFalse,
      );
    });

    test('drag-release commit always opens immediately', () {
      // dragging==false is the release-commit path: the throttle must never
      // swallow the finger's final position, even right after a live jump.
      expect(
        vmCrossJumpStashes(dragging: false, withinThrottleWindow: true),
        isFalse,
      );
      expect(
        vmCrossJumpStashes(dragging: false, withinThrottleWindow: false),
        isFalse,
      );
    });
  });
}

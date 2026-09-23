import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/background_playback/services/background_lock_mapping.dart';

/// 进度锁定 (`full`) foreground→副音 mapping: a fixed offset over the
/// concatenated 副音 queue, with rollover/wrap on overflow.
void main() {
  // Queue: A 3:00, B 3:00, C 3:00  (total 9:00).
  const threeMinutes = 3 * 60 * 1000;
  final timeline = BgQueueTimeline(
    const [threeMinutes, threeMinutes, threeMinutes],
  );

  group('BgQueueTimeline', () {
    test('prefix sums and offsets', () {
      expect(timeline.totalMs, 9 * 60 * 1000);
      expect(timeline.offsetOf(0), 0);
      expect(timeline.offsetOf(1), threeMinutes);
      expect(timeline.offsetOf(2), 2 * threeMinutes);
      expect(timeline.offsetOf(99), 0);
    });

    test('locate maps a virtual position to (index, local)', () {
      expect(timeline.locate(0), (0, 0));
      expect(timeline.locate(1000), (0, 1000));
      expect(timeline.locate(threeMinutes), (1, 0),
          reason: 'boundary resolves to the later entry');
      expect(timeline.locate(threeMinutes + 500), (1, 500));
      expect(timeline.locate(9 * 60 * 1000), (2, threeMinutes),
          reason: 'past-end clamps to the last file end');
    });

    test('virtualPositionOf is the inverse of locate', () {
      expect(timeline.virtualPositionOf(1, 500), threeMinutes + 500);
      expect(timeline.virtualPositionOf(0, threeMinutes), threeMinutes);
    });

    test('unknown (zero) durations collapse without breaking offsets', () {
      final t = BgQueueTimeline(const [threeMinutes, 0, threeMinutes]);
      expect(t.totalMs, 6 * 60 * 1000);
      expect(t.locate(threeMinutes), (2, 0),
          reason: 'the 0-length entry is skipped at the boundary');
    });

    test('empty timeline degrades to (0,0)', () {
      final t = BgQueueTimeline(const []);
      expect(t.isEmpty, isTrue);
      expect(t.totalMs, 0);
      expect(t.locate(1234), (0, 0));
      expect(t.virtualPositionOf(3, 999), 0);
    });
  });

  group('resolveLockTarget (fixed offset)', () {
    test('same-file seek keeps the offset', () {
      // fg 10:00, a 6:00 offset -> bg virtual 4:00 -> file B at 1:00.
      final target = resolveLockTarget(
        fgMs: 10 * 60 * 1000,
        offsetMs: 6 * 60 * 1000,
        timeline: timeline,
      );
      expect(target.fileIndex, 1);
      expect(target.localMs, 1 * 60 * 1000);
      expect(target.wrapped, isFalse);
    });

    test('a +10s/-10s skip shifts by the same amount', () {
      const offset = 6 * 60 * 1000;
      final fwd = resolveLockTarget(
        fgMs: 10 * 60 * 1000 + 10000,
        offsetMs: offset,
        timeline: timeline,
      );
      final back = resolveLockTarget(
        fgMs: 10 * 60 * 1000 - 10000,
        offsetMs: offset,
        timeline: timeline,
      );
      expect(fwd.localMs, 1 * 60 * 1000 + 10000);
      expect(back.localMs, 1 * 60 * 1000 - 10000);
    });

    test('overflow rolls forward into the next file', () {
      // fg 10:00, offset 0 -> bg virtual 10:00 -> file 3... only 3 files.
      final target = resolveLockTarget(
        fgMs: 8 * 60 * 1000,
        offsetMs: 0,
        timeline: timeline,
      );
      expect(target.fileIndex, 2);
      expect(target.localMs, 2 * 60 * 1000);
    });

    test('negative target clamps to the queue head', () {
      final target = resolveLockTarget(
        fgMs: 1000,
        offsetMs: 10 * 60 * 1000,
        timeline: timeline,
      );
      expect(target.fileIndex, 0);
      expect(target.localMs, 0);
    });

    test('overflow clamps to the tail without wrap', () {
      final target = resolveLockTarget(
        fgMs: 20 * 60 * 1000,
        offsetMs: 0,
        timeline: timeline,
      );
      expect(target.fileIndex, 2);
      expect(target.localMs, threeMinutes, reason: 'clamped to the end');
      expect(target.wrapped, isFalse);
    });

    test('overflow wraps to the head under repeat-all', () {
      final target = resolveLockTarget(
        fgMs: 10 * 60 * 1000,
        offsetMs: 0,
        timeline: timeline,
        wrap: true,
      );
      expect(target.wrapped, isTrue);
      expect(target.virtualMs, 60 * 1000);
      expect(target.fileIndex, 0);
      expect(target.localMs, 60 * 1000);
    });

    test('empty timeline never throws', () {
      final target = resolveLockTarget(
        fgMs: 1234,
        offsetMs: 5678,
        timeline: BgQueueTimeline(const []),
      );
      expect(target, const BgLockTarget(0, 0, 0, false));
    });
  });

  test('bgLockTargetRolls reports a file change', () {
    const t = BgLockTarget(1, 0, 0, false);
    expect(bgLockTargetRolls(t, 1), isFalse);
    expect(bgLockTargetRolls(t, 0), isTrue);
  });
}

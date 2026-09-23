import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/scenario_playback/playback/playback_progress.dart';

/// RED tests for the playback position lock (位置意图锁).
///
/// Contract: while an explicit position intent exists (open resume, VM
/// pre-write, user seek, drag release), every progress write for the file is
/// blocked until the player has been observed ONCE at the intended position.
/// Unlock-by-issue (the old OpenResumeGate) left the write window open when a
/// seek failed or landed late — the root of the "switch plays from head" bug.
void main() {
  group('isLandingAt (pure landing decision)', () {
    test('mid-file target lands within tolerance', () {
      expect(
        isLandingAt(posMs: 42833, targetMs: 42833, durationMs: 72661),
        isTrue,
      );
      expect(
        isLandingAt(posMs: 42833 + 1500, targetMs: 42833, durationMs: 72661),
        isTrue,
      );
      expect(
        isLandingAt(posMs: 42833 - 1500, targetMs: 42833, durationMs: 72661),
        isTrue,
      );
    });

    test('overshoot beyond tolerance does not land', () {
      // Position kept playing from an old spot (seek never landed).
      expect(
        isLandingAt(posMs: 50000, targetMs: 42833, durationMs: 72661),
        isFalse,
      );
    });

    test('far-before target does not land', () {
      expect(
        isLandingAt(posMs: 533, targetMs: 42833, durationMs: 72661),
        isFalse,
      );
    });

    test('target 0 lands for head positions up to the head cap', () {
      expect(isLandingAt(posMs: 0, targetMs: 0, durationMs: 72661), isTrue);
      expect(isLandingAt(posMs: 533, targetMs: 0, durationMs: 72661), isTrue);
      expect(
        isLandingAt(
            posMs: 2500, targetMs: 0, durationMs: 72661),
        isTrue,
      );
    });

    test('target 0 does not land mid-file', () {
      expect(
        isLandingAt(posMs: 42833, targetMs: 0, durationMs: 72661),
        isFalse,
      );
    });

    test('file end counts as landed for any target', () {
      expect(
        isLandingAt(posMs: 72661 - 200, targetMs: 10000, durationMs: 72661),
        isTrue,
      );
    });

    test('unknown duration still lands by tolerance', () {
      expect(isLandingAt(posMs: 42833, targetMs: 42833, durationMs: 0), isTrue);
      expect(isLandingAt(posMs: 533, targetMs: 42833, durationMs: 0), isFalse);
    });
  });

  group('PlaybackPositionLock', () {
    test('a fresh lock does not block writes', () {
      final lock = PlaybackPositionLock();
      expect(lock.phase, PositionLockPhase.unlocked);
      expect(lock.blocksWrites, isFalse);
    });

    test('armPending blocks writes with unknown target', () {
      final lock = PlaybackPositionLock();
      lock.armPending();
      expect(lock.phase, PositionLockPhase.pending);
      expect(lock.targetMs, isNull);
      expect(lock.blocksWrites, isTrue);
    });

    test('armTarget blocks until landing, unlock on landing', () {
      final lock = PlaybackPositionLock();
      lock.armPending();
      lock.armTarget(42833);
      expect(lock.phase, PositionLockPhase.locked);
      expect(lock.targetMs, 42833);
      expect(lock.blocksWrites, isTrue);
      // Pre-land head sample: still locked.
      expect(lock.checkLanding(533, 72661), isFalse);
      expect(lock.blocksWrites, isTrue);
      // Seek landed: unlocked exactly once.
      expect(lock.checkLanding(42900, 72661), isTrue);
      expect(lock.phase, PositionLockPhase.unlocked);
      expect(lock.blocksWrites, isFalse);
    });

    test('fromBeginningExplicit target 0 lands at the head', () {
      final lock = PlaybackPositionLock();
      lock.armTarget(0);
      expect(lock.checkLanding(120, 72661), isTrue);
      expect(lock.phase, PositionLockPhase.unlocked);
    });

    test('checkLanding is a no-op while unlocked', () {
      final lock = PlaybackPositionLock();
      expect(lock.checkLanding(42833, 72661), isFalse);
      expect(lock.phase, PositionLockPhase.unlocked);
    });

    test('explicit unlock works from pending and locked', () {
      final lock = PlaybackPositionLock();
      lock.armPending();
      lock.unlock();
      expect(lock.blocksWrites, isFalse);
      lock.armTarget(1000);
      lock.unlock();
      expect(lock.blocksWrites, isFalse);
      expect(lock.targetMs, isNull);
    });

    test('pending timeout releases fail-open', () {
      final lock = PlaybackPositionLock();
      final open = DateTime(2026, 1, 1, 12);
      lock.armPending(now: open);
      // Duration never arrives: 8s later the lock must release so saves
      // cannot stay frozen for the whole session.
      expect(
        lock.tickTimeout(now: open.add(const Duration(seconds: 7))),
        PositionLockTimeoutAction.none,
      );
      expect(lock.blocksWrites, isTrue);
      expect(
        lock.tickTimeout(now: open.add(const Duration(seconds: 9))),
        PositionLockTimeoutAction.released,
      );
      expect(lock.blocksWrites, isFalse);
    });

    test('locked timeout retries the seek once, then releases', () {
      final lock = PlaybackPositionLock();
      final t0 = DateTime(2026, 1, 1, 12);
      lock.armTarget(42833, now: t0);
      expect(
        lock.tickTimeout(now: t0.add(const Duration(seconds: 4))),
        PositionLockTimeoutAction.none,
      );
      expect(
        lock.tickTimeout(now: t0.add(const Duration(seconds: 6))),
        PositionLockTimeoutAction.retrySeek,
      );
      // Still locked after the retry is armed.
      expect(lock.blocksWrites, isTrue);
      // Retry seek issued; another full window without landing releases.
      expect(
        lock.tickTimeout(now: t0.add(const Duration(seconds: 10))),
        PositionLockTimeoutAction.none,
      );
      expect(
        lock.tickTimeout(now: t0.add(const Duration(seconds: 12))),
        PositionLockTimeoutAction.released,
      );
      expect(lock.blocksWrites, isFalse);
    });

    test('re-armTarget resets the retry budget', () {
      final lock = PlaybackPositionLock();
      final t0 = DateTime(2026, 1, 1, 12);
      lock.armTarget(1000, now: t0);
      expect(
        lock.tickTimeout(now: t0.add(const Duration(seconds: 6))),
        PositionLockTimeoutAction.retrySeek,
      );
      // A NEW user intent (e.g. another seek) re-arms from scratch.
      lock.armTarget(20000, now: t0.add(const Duration(seconds: 6)));
      expect(
        lock.tickTimeout(now: t0.add(const Duration(seconds: 7))),
        PositionLockTimeoutAction.none,
      );
      expect(lock.blocksWrites, isTrue);
    });

    test('landing after retry releases', () {
      final lock = PlaybackPositionLock();
      lock.armTarget(42833, now: DateTime(2026, 1, 1, 12));
      expect(
        lock.tickTimeout(now: DateTime(2026, 1, 2)),
        PositionLockTimeoutAction.retrySeek,
      );
      expect(lock.checkLanding(42900, 72661), isTrue);
      expect(lock.blocksWrites, isFalse);
    });
  });
}

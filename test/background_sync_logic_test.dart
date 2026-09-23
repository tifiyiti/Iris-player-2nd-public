import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/background_playback/model/enum/bg_seek_link.dart';
import 'package:iris/features/background_playback/model/enum/bg_step_mode.dart';
import 'package:iris/features/background_playback/services/background_sync_logic.dart';

/// 进度联动 (progress lock, split into two axes) — how much of the two
/// runtimes' transport is shared.
///
/// linked + high → play/pause AND seek forward/back step follow the foreground
///                 (feels like one media with a natural second track);
/// linked + low  → only play/pause is shared, seeks stay free so the user can
///                 nudge alignment;
/// independent   → nothing is shared (the level is then inert).
void main() {
  group('shouldSyncTransport', () {
    test('linked shares play/pause at either level', () {
      expect(shouldSyncTransport(BgSeekLink.linked), isTrue);
    });

    test('independent shares nothing', () {
      expect(shouldSyncTransport(BgSeekLink.independent), isFalse);
    });
  });

  group('shouldSyncPosition', () {
    test('only linked + high mirrors seeks', () {
      expect(
        shouldSyncPosition(link: BgSeekLink.linked, level: BgLockLevel.high),
        isTrue,
      );
      expect(
        shouldSyncPosition(link: BgSeekLink.linked, level: BgLockLevel.low),
        isFalse,
      );
      expect(
        shouldSyncPosition(
            link: BgSeekLink.independent, level: BgLockLevel.high),
        isFalse,
      );
    });
  });

  group('isPositionJump', () {
    test('a plain forward tick within tolerance is not a jump', () {
      expect(
        isPositionJump(
          prevMs: 1000,
          posMs: 1500,
          elapsedMs: 500,
          rate: 1.0,
        ),
        isFalse,
      );
    });

    test('a large forward leap beyond the elapsed window is a jump', () {
      // Only 200ms of wall time passed but the position advanced 8s — a seek.
      expect(
        isPositionJump(
          prevMs: 1000,
          posMs: 9000,
          elapsedMs: 200,
          rate: 1.0,
        ),
        isTrue,
      );
    });

    test('a backward move is always a jump', () {
      expect(
        isPositionJump(
          prevMs: 5000,
          posMs: 1000,
          elapsedMs: 100,
          rate: 1.0,
        ),
        isTrue,
      );
    });

    test('a paused sample (no advance) is not a jump', () {
      expect(
        isPositionJump(
          prevMs: 5000,
          posMs: 5000,
          elapsedMs: 400,
          rate: 1.0,
        ),
        isFalse,
      );
    });

    test('playback rate scales the expected advance', () {
      // At 2x, 1s of wall time legitimately advances ~2s of media.
      expect(
        isPositionJump(
          prevMs: 0,
          posMs: 2000,
          elapsedMs: 1000,
          rate: 2.0,
        ),
        isFalse,
      );
      // …but 5s is still far beyond that window.
      expect(
        isPositionJump(
          prevMs: 0,
          posMs: 5000,
          elapsedMs: 1000,
          rate: 2.0,
        ),
        isTrue,
      );
    });

    test('the first sample (no previous) is never a jump', () {
      expect(
        isPositionJump(
          prevMs: null,
          posMs: 42000,
          elapsedMs: 0,
          rate: 1.0,
        ),
        isFalse,
      );
    });
  });

  group('shouldPauseBgPastWindow', () {
    test('a zero offset pauses just past the raw fg duration', () {
      expect(
        shouldPauseBgPastWindow(
            bgVirtualMs: 100000, fgDurMs: 100000, offsetMs: 0),
        isFalse,
      );
      expect(
        shouldPauseBgPastWindow(
            bgVirtualMs: 100751, fgDurMs: 100000, offsetMs: 0),
        isTrue,
      );
    });

    test('a positive offset pauses at the MAPPED window end', () {
      // fg runs 10s ahead of bg (offset +10000): fg 100% maps to bg 90s, so
      // the old raw comparison (bg > fgDur) let it sound 10s too long.
      expect(
        shouldPauseBgPastWindow(
            bgVirtualMs: 90000, fgDurMs: 100000, offsetMs: 10000),
        isFalse,
      );
      expect(
        shouldPauseBgPastWindow(
            bgVirtualMs: 90751, fgDurMs: 100000, offsetMs: 10000),
        isTrue,
      );
      expect(
        shouldPauseBgPastWindow(
            bgVirtualMs: 95000, fgDurMs: 100000, offsetMs: 10000),
        isTrue,
      );
    });

    test('a negative offset keeps 副音 until the mapped end', () {
      // bg ahead by 10s: fg 100% maps to bg 110s.
      expect(
        shouldPauseBgPastWindow(
            bgVirtualMs: 110000, fgDurMs: 100000, offsetMs: -10000),
        isFalse,
      );
      expect(
        shouldPauseBgPastWindow(
            bgVirtualMs: 110751, fgDurMs: 100000, offsetMs: -10000),
        isTrue,
      );
    });
  });

  group('shouldMirrorTransport', () {
    test('mirrors only a real difference in the playing flag', () {
      expect(shouldMirrorTransport(fgPlaying: true, bgPlaying: false), isTrue);
      expect(shouldMirrorTransport(fgPlaying: false, bgPlaying: true), isTrue);
      expect(shouldMirrorTransport(fgPlaying: true, bgPlaying: true), isFalse);
      expect(shouldMirrorTransport(fgPlaying: false, bgPlaying: false), isFalse);
    });
  });

  group('shouldMirrorPosition', () {
    test('mirrors only when the two drift past the tolerance', () {
      expect(
        shouldMirrorPosition(fgMs: 10000, bgMs: 10050, toleranceMs: 250),
        isFalse,
      );
      expect(
        shouldMirrorPosition(fgMs: 10000, bgMs: 12000, toleranceMs: 250),
        isTrue,
      );
    });
  });

  // A discrete step is an ACTION, separate from the continuous seek link: the
  // default `swapOnly` confines it to the 副音 track, while `followLink` lets
  // it ride the lock.
  group('shouldMirrorStep', () {
    test('swapOnly never mirrors a step, whatever the link axis says', () {
      expect(
        shouldMirrorStep(
          stepMode: BgStepMode.swapOnly,
          link: BgSeekLink.linked,
          level: BgLockLevel.high,
        ),
        isFalse,
      );
      expect(
        shouldMirrorStep(
          stepMode: BgStepMode.swapOnly,
          link: BgSeekLink.linked,
          level: BgLockLevel.low,
        ),
        isFalse,
      );
      expect(
        shouldMirrorStep(
          stepMode: BgStepMode.swapOnly,
          link: BgSeekLink.independent,
          level: BgLockLevel.high,
        ),
        isFalse,
      );
    });

    test('followLink mirrors only under linked + high', () {
      expect(
        shouldMirrorStep(
          stepMode: BgStepMode.followLink,
          link: BgSeekLink.linked,
          level: BgLockLevel.high,
        ),
        isTrue,
      );
      expect(
        shouldMirrorStep(
          stepMode: BgStepMode.followLink,
          link: BgSeekLink.linked,
          level: BgLockLevel.low,
        ),
        isFalse,
      );
      expect(
        shouldMirrorStep(
          stepMode: BgStepMode.followLink,
          link: BgSeekLink.independent,
          level: BgLockLevel.high,
        ),
        isFalse,
      );
    });
  });
}

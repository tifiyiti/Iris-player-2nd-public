import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/background_playback/model/enum/bg_align_default.dart';
import 'package:iris/features/background_playback/model/enum/bg_align_mode.dart';
import 'package:iris/features/background_playback/model/enum/bg_exhausted_action.dart';
import 'package:iris/features/background_playback/services/background_alignment.dart';

/// 副音 alignment start position + the mandatory remaining-time threshold.
///
/// The mode is applied on every alignment (first file of a run, or a user
/// switch): `target = fgPos - (fgAnchor - bgAnchor)`, clamped into the file.
/// A natural completion is owned by the scope (BgExhaustedAction), not here.
void main() {
  group('bgAlignTargetMs', () {
    test('fromFgHead seeks the 副音 to the fg position (same timeline)', () {
      expect(
        bgAlignTargetMs(
          mode: BgAlignMode.fromFgHead,
          fgPosMs: 40000,
          bgDurMs: 900000,
          percent: 30,
        ),
        40000,
      );
    });

    test('atFgPosition starts the file at its own 00:00', () {
      expect(
        bgAlignTargetMs(
          mode: BgAlignMode.atFgPosition,
          fgPosMs: 40000,
          bgDurMs: 900000,
          percent: 30,
        ),
        0,
      );
    });

    test('bgPercent starts at the remembered share', () {
      expect(
        bgAlignTargetMs(
          mode: BgAlignMode.bgPercent,
          fgPosMs: 40000,
          bgDurMs: 900000,
          percent: 30,
        ),
        270000,
      );
    });

    test('a target past the 副音 file is clamped to its end', () {
      expect(
        bgAlignTargetMs(
          mode: BgAlignMode.fromFgHead,
          fgPosMs: 1000000,
          bgDurMs: 900000,
          percent: 30,
        ),
        900000,
      );
    });

    test('an unknown 副音 duration degrades to 0', () {
      expect(
        bgAlignTargetMs(
          mode: BgAlignMode.fromFgHead,
          fgPosMs: 40000,
          bgDurMs: 0,
          percent: 30,
        ),
        0,
      );
    });
  });

  group('defaultForAlignMode', () {
    test('round-trips the persisted default one-to-one', () {
      for (final m in BgAlignMode.values) {
        expect(modeForAlignDefault(defaultForAlignMode(m)), m);
      }
      expect(defaultForAlignMode(BgAlignMode.fromFgHead), BgAlignDefault.fgHead);
      expect(
        defaultForAlignMode(BgAlignMode.atFgPosition),
        BgAlignDefault.fgPosition,
      );
      expect(
        defaultForAlignMode(BgAlignMode.bgPercent),
        BgAlignDefault.bgPercent,
      );
    });
  });

  group('alignPercentTargetMs', () {
    test('clamps the share into 0..100', () {
      expect(alignPercentTargetMs(600000, -5), 0);
      expect(alignPercentTargetMs(600000, 0), 0);
      expect(alignPercentTargetMs(600000, 50), 300000);
      expect(alignPercentTargetMs(600000, 100), 600000);
      expect(alignPercentTargetMs(600000, 250), 600000);
    });
  });

  // The mandatory "对齐后 bg 可播放时间 < xxx" threshold: remaining =
  // bgDur - bgPos.
  group('shouldWarnBgRunningOut', () {
    test('warns once the remaining time is below the threshold', () {
      expect(
        shouldWarnBgRunningOut(bgDurMs: 600000, bgPosMs: 596000, thresholdSec: 5),
        isTrue,
      );
      expect(
        shouldWarnBgRunningOut(bgDurMs: 600000, bgPosMs: 590000, thresholdSec: 5),
        isFalse,
      );
    });

    test('a threshold of 0 still warns within a second (never disabled)', () {
      expect(
        shouldWarnBgRunningOut(bgDurMs: 600000, bgPosMs: 599500, thresholdSec: 0),
        isTrue,
      );
    });

    test('an unknown duration never warns', () {
      expect(
        shouldWarnBgRunningOut(bgDurMs: 0, bgPosMs: 0, thresholdSec: 5),
        isFalse,
      );
    });
  });

  // The prompt is suppressed under nextBg (the continuation is automatic) and
  // kept under stopRestoreFg (the user must learn 副音 will stop).
  group('shouldRaiseAlignThreshold', () {
    bool raise(BgExhaustedAction action) => shouldRaiseAlignThreshold(
          enabled: true,
          gateOpen: true,
          exhaustedAction: action,
          bgDurMs: 600000,
          bgPosMs: 599500,
          thresholdSec: 5,
        );

    test('nextBg never raises the prompt', () {
      expect(raise(BgExhaustedAction.nextBg), isFalse);
    });

    test('stopRestoreFg raises it when the remainder is below the threshold', () {
      expect(raise(BgExhaustedAction.stopRestoreFg), isTrue);
    });

    test('a disabled subsystem or a closed gate never raises it', () {
      expect(
        shouldRaiseAlignThreshold(
          enabled: false,
          gateOpen: true,
          exhaustedAction: BgExhaustedAction.stopRestoreFg,
          bgDurMs: 600000,
          bgPosMs: 599500,
          thresholdSec: 5,
        ),
        isFalse,
      );
      expect(
        shouldRaiseAlignThreshold(
          enabled: true,
          gateOpen: false,
          exhaustedAction: BgExhaustedAction.stopRestoreFg,
          bgDurMs: 600000,
          bgPosMs: 599500,
          thresholdSec: 5,
        ),
        isFalse,
      );
    });
  });

  group('clampAlignWarnRemainSec', () {
    test('floors at 1s and caps at 120s (cannot be off)', () {
      expect(clampAlignWarnRemainSec(0), 1);
      expect(clampAlignWarnRemainSec(-5), 1);
      expect(clampAlignWarnRemainSec(5), 5);
      expect(clampAlignWarnRemainSec(500), 120);
    });
  });

  group('resolveBgAlignmentChoice (VM tiled manual)', () {
    test('from-head starts the 副音 file at 00:00', () {
      expect(
        resolveBgAlignmentChoice(
          choice: BgAlignChoice.fromHead,
          bgDurMs: 600000,
        ),
        0,
      );
    });

    test('percent starts at percent% of the 副音 file', () {
      expect(
        resolveBgAlignmentChoice(
          choice: BgAlignChoice.percent,
          bgDurMs: 600000,
          percent: 30,
        ),
        180000,
      );
    });

    test('an unknown duration degrades to the head', () {
      expect(
        resolveBgAlignmentChoice(
          choice: BgAlignChoice.percent,
          bgDurMs: 0,
          percent: 30,
        ),
        0,
      );
    });
  });

  group('bgEffectiveRemainingMs', () {
    test('without a window the raw file remainder applies', () {
      expect(
        bgEffectiveRemainingMs(bgDurMs: 600000, bgPosMs: 100000),
        500000,
      );
    });

    test('a 仅当前 ceiling caps the playable remainder', () {
      expect(
        bgEffectiveRemainingMs(
          bgDurMs: 600000,
          bgPosMs: 100000,
          ceilingLocalMs: 103000,
        ),
        3000,
      );
    });

    test('parked past the ceiling floors at zero (nothing playable)', () {
      expect(
        bgEffectiveRemainingMs(
          bgDurMs: 600000,
          bgPosMs: 200000,
          ceilingLocalMs: 103000,
        ),
        0,
      );
    });
  });

  group('shouldWarnBgRunningOut with a window ceiling', () {
    test('warns on the window remainder, not the raw remainder', () {
      // Raw remainder is ample (500s) but the window leaves 3s < 5s.
      expect(
        shouldWarnBgRunningOut(
          bgDurMs: 600000,
          bgPosMs: 100000,
          thresholdSec: 5,
          ceilingLocalMs: 103000,
        ),
        isTrue,
      );
    });

    test('stays quiet when the window remainder is ample', () {
      expect(
        shouldWarnBgRunningOut(
          bgDurMs: 600000,
          bgPosMs: 100000,
          thresholdSec: 5,
          ceilingLocalMs: 200000,
        ),
        isFalse,
      );
    });
  });

  group('modalCloseNeedsRealign', () {
    test('realigns when the file changed behind the modal', () {
      expect(
        modalCloseNeedsRealign(
          entryKey: 'a',
          exitKey: 'b',
          enabled: true,
          bgExhausted: false,
        ),
        isTrue,
      );
    });

    test('stays put when the file is unchanged, disabled, or terminal', () {
      expect(
        modalCloseNeedsRealign(
          entryKey: 'a',
          exitKey: 'a',
          enabled: true,
          bgExhausted: false,
        ),
        isFalse,
      );
      expect(
        modalCloseNeedsRealign(
          entryKey: 'a',
          exitKey: 'b',
          enabled: false,
          bgExhausted: false,
        ),
        isFalse,
      );
      expect(
        modalCloseNeedsRealign(
          entryKey: 'a',
          exitKey: 'b',
          enabled: true,
          bgExhausted: true,
        ),
        isFalse,
      );
      expect(
        modalCloseNeedsRealign(
          entryKey: null,
          exitKey: 'b',
          enabled: true,
          bgExhausted: false,
        ),
        isFalse,
      );
    });
  });

  group('shouldRestoreBgAfterModal', () {
    test('a terminal run is never revived, even when it was playing', () {
      expect(
        shouldRestoreBgAfterModal(bgWasPlaying: true, bgExhausted: true),
        isFalse,
      );
    });

    test('a live run resumes only when it was playing', () {
      expect(
        shouldRestoreBgAfterModal(bgWasPlaying: true, bgExhausted: false),
        isTrue,
      );
      expect(
        shouldRestoreBgAfterModal(bgWasPlaying: false, bgExhausted: false),
        isFalse,
      );
    });

    test('a gate closed behind the modal blocks the 副音 restore', () {
      expect(
        shouldRestoreBgAfterModal(
          bgWasPlaying: true,
          bgExhausted: false,
          gateOpen: false,
        ),
        isFalse,
        reason: 'a stop pressed while the dialog was up owns the transport',
      );
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/background_playback/model/enum/bg_seek_link.dart';
import 'package:iris/features/background_playback/services/background_sync_logic.dart';

/// 副音 × scrub-drag cooperation: the policy is derived purely from the link
/// axes, and the drag stands the position mirror down regardless of policy.
void main() {
  group('resolveBgScrubPolicy', () {
    test('disabled pair never participates', () {
      expect(
        resolveBgScrubPolicy(
            enabled: false, link: BgSeekLink.linked, level: BgLockLevel.high),
        BgScrubPolicy.none,
      );
    });

    test('independent link never participates', () {
      expect(
        resolveBgScrubPolicy(
            enabled: true,
            link: BgSeekLink.independent,
            level: BgLockLevel.high),
        BgScrubPolicy.none,
      );
    });

    test('linked + low is pause-only (resume 副音 at its own position)', () {
      expect(
        resolveBgScrubPolicy(
            enabled: true, link: BgSeekLink.linked, level: BgLockLevel.low),
        BgScrubPolicy.pauseBgFollows,
      );
    });

    test('linked + high follows the drag AND must land aligned', () {
      expect(
        resolveBgScrubPolicy(
            enabled: true, link: BgSeekLink.linked, level: BgLockLevel.high),
        BgScrubPolicy.followWithProgress,
      );
    });
  });

  group('resolveBgMirrorAction standDown', () {
    BgMirrorAction decide({required bool standDown}) => resolveBgMirrorAction(
          enabled: true,
          positionSync: true,
          standDown: standDown,
          bgIsMaster: false,
          fgJump: true,
          bgJump: false,
          fgSystemSeekLanding: false,
          bgSystemSeekLanding: false,
          pendingStep: false,
          mirrorStep: false,
          lockOffsetReady: true,
        );

    test('a scrub drag suppresses the fg-jump mirror (no bg dragging)', () {
      expect(decide(standDown: true), BgMirrorAction.none);
    });

    test('the release edge mirrors again (one-shot alignment)', () {
      expect(decide(standDown: false), BgMirrorAction.fgDrivesBg);
    });
  });

  group('post-drag 高同步 realignment', () {
    test('a settled sample past the drift tolerance corrects in the master direction', () {
      // No jump on either side (the drag already moved the fg), but the bg was
      // held still for the whole gesture → the drift branch realigns once.
      final BgMirrorAction action = resolveBgMirrorAction(
        enabled: true,
        positionSync: true,
        standDown: false,
        bgIsMaster: false,
        fgJump: false,
        bgJump: false,
        fgSystemSeekLanding: false,
        bgSystemSeekLanding: false,
        pendingStep: false,
        mirrorStep: false,
        lockOffsetReady: true,
        driftMs: 30000,
      );
      expect(action, BgMirrorAction.fgDrivesBg);
    });

    test('a small drift only re-anchors', () {
      final BgMirrorAction action = resolveBgMirrorAction(
        enabled: true,
        positionSync: true,
        standDown: false,
        bgIsMaster: false,
        fgJump: false,
        bgJump: false,
        fgSystemSeekLanding: false,
        bgSystemSeekLanding: false,
        pendingStep: false,
        mirrorStep: false,
        lockOffsetReady: true,
        driftMs: 120,
      );
      expect(action, BgMirrorAction.anchor);
    });
  });
}

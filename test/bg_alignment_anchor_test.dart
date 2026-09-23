import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/background_playback/model/enum/bg_align_default.dart';
import 'package:iris/features/background_playback/model/enum/bg_align_mode.dart';
import 'package:iris/features/background_playback/services/background_alignment.dart';
import 'package:iris/features/background_playback/services/background_lock_mapping.dart';

/// 对齐锚点模型 (P1): `(fgAnchor, bgAnchor)` → offset `fg - bg`, and the
/// 仅当前 floor paired with the existing ceiling. bg positions are always
/// derived from the fg progress and the anchor — never stored progress.
void main() {
  group('resolveAlignmentAnchor / alignmentOffsetMs', () {
    test('00:00 mode maps both origins (offset 0)', () {
      final a = resolveAlignmentAnchor(
        mode: BgAlignMode.fromFgHead,
        currentFgMs: 120000,
        bgDurMs: 300000,
        percent: 30,
      );
      expect(a.fgAnchorMs, 0);
      expect(a.bgAnchorMs, 0);
      expect(
          alignmentOffsetMs(fgAnchorMs: a.fgAnchorMs, bgAnchorMs: a.bgAnchorMs),
          0);
    });

    test('at-position mode anchors bg 00:00 at the current fg moment', () {
      final a = resolveAlignmentAnchor(
        mode: BgAlignMode.atFgPosition,
        currentFgMs: 120000,
        bgDurMs: 300000,
        percent: 30,
      );
      expect(a.fgAnchorMs, 120000);
      expect(a.bgAnchorMs, 0);
      expect(
          alignmentOffsetMs(fgAnchorMs: a.fgAnchorMs, bgAnchorMs: a.bgAnchorMs),
          120000);
    });

    test('bg-percent mode anchors the current fg moment at 30% of the bg', () {
      final a = resolveAlignmentAnchor(
        mode: BgAlignMode.bgPercent,
        currentFgMs: 120000,
        bgDurMs: 300000,
        percent: 30,
      );
      expect(a.fgAnchorMs, 120000);
      expect(a.bgAnchorMs, 90000);
      // bg target for the current fg = fgPos - offset = 90000 (the share).
      final offset =
          alignmentOffsetMs(fgAnchorMs: a.fgAnchorMs, bgAnchorMs: a.bgAnchorMs);
      expect(120000 - offset, 90000);
    });

    test('a negative fg moment floors at 0', () {
      final a = resolveAlignmentAnchor(
        mode: BgAlignMode.atFgPosition,
        currentFgMs: -5,
        bgDurMs: 300000,
        percent: 30,
      );
      expect(a.fgAnchorMs, 0);
    });
  });

  group('modeForAlignDefault', () {
    test('maps the persisted default one-to-one onto anchor modes', () {
      expect(modeForAlignDefault(BgAlignDefault.fgHead),
          BgAlignMode.fromFgHead);
      expect(modeForAlignDefault(BgAlignDefault.fgPosition),
          BgAlignMode.atFgPosition);
      expect(
          modeForAlignDefault(BgAlignDefault.bgPercent), BgAlignMode.bgPercent);
    });
  });

  group('bgAlignDefaultFromName (legacy migration)', () {
    test('a legacy ask keeps the new default (fgHead)', () {
      expect(bgAlignDefaultFromName('ask'), BgAlignDefault.fgHead);
    });

    test('legacy fromHead/fromMid map onto the new modes', () {
      expect(bgAlignDefaultFromName('fromHead'), BgAlignDefault.fgPosition);
      expect(bgAlignDefaultFromName('fromMid'), BgAlignDefault.bgPercent);
    });

    test('current names decode directly; unknown/absent yield null', () {
      expect(bgAlignDefaultFromName('fgHead'), BgAlignDefault.fgHead);
      expect(bgAlignDefaultFromName('bgPercent'), BgAlignDefault.bgPercent);
      expect(bgAlignDefaultFromName('nonsense'), isNull);
      expect(bgAlignDefaultFromName(null), isNull);
    });
  });

  group('bgSeekFloorLocalMs', () {
    test('a positive offset floors inside the first bg file', () {
      // offset 120000 (fg runs ahead by 2min): fg 00:00 maps to bg virtual
      // -120000, i.e. 2min before the head → no lower room.
      final timeline = BgQueueTimeline(const [600000]);
      expect(
        bgSeekFloorLocalMs(
          timeline: timeline,
          currentIndex: 0,
          offsetMs: 120000,
        ),
        0,
      );
    });

    test('a negative offset floors at the mapped fg head', () {
      // offset -120000: fg 00:00 maps to bg virtual +120000 → bg local 2min.
      final timeline = BgQueueTimeline(const [600000]);
      expect(
        bgSeekFloorLocalMs(
          timeline: timeline,
          currentIndex: 0,
          offsetMs: -120000,
        ),
        120000,
      );
    });

    test('the floor accounts for the queue prefix of later files', () {
      final timeline = BgQueueTimeline(const [300000, 300000]);
      // Second file starts at virtual 5min; fg 00:00 maps to virtual 5min.
      expect(
        bgSeekFloorLocalMs(
          timeline: timeline,
          currentIndex: 1,
          offsetMs: -300000,
        ),
        0,
      );
      // fg 00:00 maps to virtual 6min → second file local 1min.
      expect(
        bgSeekFloorLocalMs(
          timeline: timeline,
          currentIndex: 1,
          offsetMs: -360000,
        ),
        60000,
      );
    });

    test('unknown timeline yields no floor', () {
      expect(
        bgSeekFloorLocalMs(
          timeline: BgQueueTimeline(const []),
          currentIndex: 0,
          offsetMs: 0,
        ),
        isNull,
      );
      expect(
        bgSeekFloorLocalMs(
          timeline: BgQueueTimeline(const [0]),
          currentIndex: 0,
          offsetMs: 0,
        ),
        isNull,
      );
    });
  });
}

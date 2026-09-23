import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/background_playback/engine/background_scope_logic.dart';
import 'package:iris/features/background_playback/model/enum/bg_apply_scope.dart';
import 'package:iris/features/background_playback/model/enum/bg_cross_action.dart';

/// 高同步下从属端到达边界（fg 到 100% / 副音映射到 fg 100% 的内容播完）时的
/// 作用域决策真值表。
void main() {
  group('resolveBgBoundaryAction', () {
    test('仅当前 stops BOTH runtimes (strict lockstep)', () {
      expect(
        resolveBgBoundaryAction(
          applyScope: BgApplyScope.currentOnly,
          bgItemSwitch: BgCrossAction.newBg,
          bgSegmentSwitch: BgCrossAction.newBg,
          transitionIsItem: true,
          fgHasSavedMapping: true,
        ),
        BgBoundaryAction.stopBoth,
      );
    });

    test('全部 follows the item switch for a new item', () {
      expect(
        resolveBgBoundaryAction(
          applyScope: BgApplyScope.all,
          bgItemSwitch: BgCrossAction.newBg,
          bgSegmentSwitch: BgCrossAction.keepPlaying,
          transitionIsItem: true,
          fgHasSavedMapping: false,
        ),
        BgBoundaryAction.newBg,
      );
      expect(
        resolveBgBoundaryAction(
          applyScope: BgApplyScope.all,
          bgItemSwitch: BgCrossAction.keepPlaying,
          bgSegmentSwitch: BgCrossAction.newBg,
          transitionIsItem: true,
          fgHasSavedMapping: false,
        ),
        BgBoundaryAction.keepPlaying,
      );
    });

    test('全部 follows the segment switch for an internal VM switch', () {
      expect(
        resolveBgBoundaryAction(
          applyScope: BgApplyScope.all,
          bgItemSwitch: BgCrossAction.keepPlaying,
          bgSegmentSwitch: BgCrossAction.newBg,
          transitionIsItem: false,
          fgHasSavedMapping: false,
        ),
        BgBoundaryAction.newBg,
      );
      expect(
        resolveBgBoundaryAction(
          applyScope: BgApplyScope.all,
          bgItemSwitch: BgCrossAction.newBg,
          bgSegmentSwitch: BgCrossAction.keepPlaying,
          transitionIsItem: false,
          fgHasSavedMapping: false,
        ),
        BgBoundaryAction.keepPlaying,
      );
    });

    test('智能 keeps playing only with a saved mapping', () {
      expect(
        resolveBgBoundaryAction(
          applyScope: BgApplyScope.smart,
          bgItemSwitch: BgCrossAction.newBg,
          bgSegmentSwitch: BgCrossAction.newBg,
          transitionIsItem: true,
          fgHasSavedMapping: true,
        ),
        BgBoundaryAction.keepPlaying,
      );
      expect(
        resolveBgBoundaryAction(
          applyScope: BgApplyScope.smart,
          bgItemSwitch: BgCrossAction.newBg,
          bgSegmentSwitch: BgCrossAction.newBg,
          transitionIsItem: true,
          fgHasSavedMapping: false,
        ),
        BgBoundaryAction.stopBoth,
      );
    });
  });
}

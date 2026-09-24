import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/background_playback/view/background_quick_bar.dart';
import 'package:iris/features/control_group/model/enum/player_control_group.dart';
import 'package:iris/features/control_group/store/use_control_group_store.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/pages/player/control_bar/control_bar_layout/control_bar_controls.dart';
import 'package:iris/pages/player/control_bar/control_bar_layout/portrait_bar_align.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/utils/platform.dart';

/// Phone-portrait / narrow bottom bar: seek slider + two button rows.
///
/// The two groups carry INDEPENDENT horizontal alignment (see
/// [PortraitBarAlign]): the normal playback rows spread/pack via
/// [portraitPlaybackRowAlign], while the group-2 副音 block is positioned by an
/// outer `Align` ([portraitSubAudioBlockAlign]) because a shrink-wrapped
/// `BalancedButtonWrap` would otherwise be centred by the `Column`. The default
/// is [PortraitBarAlign.center] — the pre-238d47c2 look. This is PORTRAIT-only:
/// the side panel and the standalone desktop 副音 row keep their own knobs.
class MobileControlLayout extends HookWidget {
  const MobileControlLayout({super.key, required this.controls});

  final ControlBarControls controls;

  @override
  Widget build(BuildContext context) {
    // Bottom control group: playback (two legacy rows) vs 副音 quick controls.
    // The standalone 副音 row is gone on phones; group 2 owns it here. Desktop
    // only honors the group after the phone-mode opt-in.
    final PlayerControlGroup group =
        useControlGroupStore().select(context, (s) => s.group);
    final AppState app = useAppStore().select(context, (s) => s);
    final bool supported = isMobilePlatform || app.desktopCenterZonePhoneMode;
    final bool showingBackgroundGroup =
        supported && group == PlayerControlGroup.background;
    // Desktop keeps its standalone quick row unless group 2 replaced it; phones
    // never show it.
    final bool showStandaloneQuickBar =
        !isMobilePlatform && !showingBackgroundGroup;

    final MainAxisAlignment playbackAlign =
        portraitPlaybackRowAlign(app.portraitPlaybackAlign);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        controls.slider,
        if (showStandaloneQuickBar) controls.backgroundQuickBar,
        if (showingBackgroundGroup)
          // The 副音 bar shrink-wraps, so its BLOCK position is owned by this
          // Align (a bare Column child would be centred regardless of the
          // wrap's own alignment). heightFactor keeps it from eating the column.
          Align(
            alignment: portraitSubAudioBlockAlign(app.portraitSubAudioAlign),
            heightFactor: 1,
            child: BackgroundQuickBar(
              axis: Axis.horizontal,
              alignment: portraitSubAudioWrapAlign(app.portraitSubAudioAlign),
              forceVisible: true,
              color: controls.color,
              overlayColor: controls.overlayColor,
            ),
          )
        else ...[
          Row(
            mainAxisAlignment: playbackAlign,
            children: [
              controls.shuffle,
              controls.prev,
              controls.playPause,
              controls.stop,
              controls.next,
              controls.repeat,
            ],
          ),
          Row(
            mainAxisAlignment: playbackAlign,
            children: [
              if (controls.showFit) controls.fit,
              controls.rotateOrVolume,
              controls.subtitle,
              controls.backgroundPlaybackMenu,
              controls.playQueue,
              controls.storage,
              if (isDesktop) controls.fullscreen,
              controls.more,
            ],
          ),
        ],
      ],
    );
  }
}

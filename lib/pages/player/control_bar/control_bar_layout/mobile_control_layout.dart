import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/background_playback/view/background_quick_bar.dart';
import 'package:iris/features/control_group/model/enum/player_control_group.dart';
import 'package:iris/features/control_group/store/use_control_group_store.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/pages/player/control_bar/control_bar_layout/control_bar_controls.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/utils/platform.dart';

/// Phone-portrait / narrow bottom bar: seek slider + two button rows.
///
/// The rows are packed to the LEFT rather than spread across the full width.
/// The bar exists for one thumb, and most users hold the phone in the right
/// hand — a left-packed group keeps every button inside the thumb's reach and
/// leaves the right half free of controls, so the natural rest position does
/// not sit on top of a button.
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        controls.slider,
        if (showStandaloneQuickBar) controls.backgroundQuickBar,
        if (showingBackgroundGroup)
          BackgroundQuickBar(
            axis: Axis.horizontal,
            // Same left-packed rule as the playback rows below.
            alignment: MainAxisAlignment.start,
            forceVisible: true,
            color: controls.color,
            overlayColor: controls.overlayColor,
          )
        else ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.start,
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
            mainAxisAlignment: MainAxisAlignment.start,
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

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

class TabletControlLayout extends HookWidget {
  const TabletControlLayout({super.key, required this.controls});

  final ControlBarControls controls;

  @override
  Widget build(BuildContext context) {
    // Same bottom-group contract as the phone layout: mobile never shows the
    // standalone 副音 row, and group 2 replaces the button row. Desktop keeps
    // the standalone row unless group 2 replaced it (phone-mode opt-in).
    final PlayerControlGroup group =
        useControlGroupStore().select(context, (s) => s.group);
    final AppState app = useAppStore().select(context, (s) => s);
    final bool supported = isMobilePlatform || app.desktopCenterZonePhoneMode;
    final bool showingBackgroundGroup =
        supported && group == PlayerControlGroup.background;
    final bool showStandaloneQuickBar =
        !isMobilePlatform && !showingBackgroundGroup;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        controls.slider,
        if (showStandaloneQuickBar) controls.backgroundQuickBar,
        const SizedBox(height: 4),
        if (showingBackgroundGroup)
          BackgroundQuickBar(
            axis: Axis.horizontal,
            alignment: MainAxisAlignment.center,
            forceVisible: true,
            color: controls.color,
            overlayColor: controls.overlayColor,
          )
        else
          Row(
            children: [
              controls.playPause,
              controls.stop,
              controls.prev,
              controls.next,
              controls.shuffle,
              controls.repeat,
              if (controls.showFit) controls.fit,
              controls.rate,
              controls.rotateOrVolume,
              const Spacer(),
              controls.subtitle,
              controls.backgroundPlaybackMenu,
              controls.playQueue,
              controls.storage,
              if (isDesktop) controls.fullscreen,
              controls.more,
            ],
          ),
      ],
    );
  }
}

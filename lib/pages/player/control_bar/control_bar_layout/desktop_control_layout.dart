import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/background_playback/view/background_quick_bar.dart';
import 'package:iris/features/control_group/model/enum/player_control_group.dart';
import 'package:iris/features/control_group/store/use_control_group_store.dart';
import 'package:iris/pages/player/control_bar/control_bar_layout/control_bar_button_row.dart';
import 'package:iris/pages/player/control_bar/control_bar_layout/control_bar_controls.dart';
import 'package:iris/pages/player/control_bar/control_bar_layout/control_bar_layout_kind.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/utils/layout_breakpoints.dart';
import 'package:iris/utils/platform.dart';

class DesktopControlLayout extends HookWidget {
  const DesktopControlLayout({super.key, required this.controls});

  final ControlBarControls controls;

  @override
  Widget build(BuildContext context) {
    // Button ordering lives in the shared left/right groups so the stacked
    // desktop layout renders the exact same arrangement.
    //
    // 副音 group 2: desktop activates the group switch under the phone-mode
    // opt-in or the dedicated desktop floating-switch flag (ships ON). While
    // active, the bar shows exactly ONE group: the forced 副音 quick bar when
    // the group is `background`, otherwise the playback row — and the
    // standalone 副音 quick row is suppressed in both cases. Only the legacy
    // configuration (neither flag on) keeps the playback row AND the
    // standalone 副音 row together.
    final bool desktopPhoneMode =
        useAppStore().select(context, (s) => s.desktopCenterZonePhoneMode);
    final store = useControlGroupStore();
    final PlayerControlGroup group = store.select(context, (s) => s.group);
    final bool floatingDesktop =
        store.select(context, (s) => s.floatingButtonDesktop);
    final bool supported = resolveControlBarGroupSupport(
      isMobile: isMobilePlatform,
      desktopPhoneMode: desktopPhoneMode,
      desktopFloatingEnabled: floatingDesktop,
    );
    final bool showingBackgroundGroup =
        supported && group == PlayerControlGroup.background;
    final bool showStandaloneQuickBar = showStandaloneQuickBarFor(
      isMobile: isMobilePlatform,
      groupSupported: supported,
    );

    // Returns to a two-row arrangement when the bar box is too narrow for the
    // inline slider + groups; the button row wraps, so it can never clip.
    return LayoutBuilder(
      builder: (context, constraints) {
        if (showingBackgroundGroup) {
          // Keep the seek axis (transport stays reachable), replace only the
          // button row with the forced 副音 quick bar — same contract as tablet.
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              controls.slider,
              const SizedBox(height: 4),
              BackgroundQuickBar(
                axis: Axis.horizontal,
                alignment: MainAxisAlignment.center,
                forceVisible: true,
                color: controls.color,
                overlayColor: controls.overlayColor,
              ),
            ],
          );
        }
        final bool singleLine =
            constraints.hasBoundedWidth && constraints.maxWidth >= kTabletBreakpoint;
        if (singleLine) {
          // 副音 quick row (问题 5): the one-line bar has no "between the slider
          // and the bar" slot, so the row goes ABOVE the main row instead.
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showStandaloneQuickBar) controls.backgroundQuickBar,
              Row(
                children: [
                  ...controls.desktopLeftButtons,
                  Expanded(child: controls.slider),
                  ...controls.desktopRightButtons,
                ],
              ),
            ],
          );
        }
        // Narrow fallback: slider on its own row + wrapping button row, still
        // keeping the left/right groups as two packed units.
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            controls.slider,
            if (showStandaloneQuickBar) controls.backgroundQuickBar,
            ControlBarGroupedRow(
              leading: controls.desktopLeftButtons,
              trailing: controls.desktopRightButtons,
            ),
          ],
        );
      },
    );
  }
}

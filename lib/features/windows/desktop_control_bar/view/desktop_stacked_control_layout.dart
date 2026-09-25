import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/background_playback/services/bg_vm_visibility.dart';
import 'package:iris/features/background_playback/store/use_background_playback_store.dart';
import 'package:iris/features/background_playback/view/background_quick_bar.dart';
import 'package:iris/features/control_group/model/enum/player_control_group.dart';
import 'package:iris/features/control_group/store/use_control_group_store.dart';
import 'package:iris/features/virtual_media/interaction/ui/vm_dual_time.dart';
import 'package:iris/features/virtual_media/store/vm_playback_store.dart';
import 'package:iris/models/player.dart';
import 'package:iris/pages/player/control_bar/control_bar_layout/control_bar_button_row.dart';
import 'package:iris/pages/player/control_bar/control_bar_layout/control_bar_controls.dart';
import 'package:iris/pages/player/control_bar/control_bar_layout/control_bar_layout_kind.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/utils/format_duration_to_minutes.dart';
import 'package:iris/utils/platform.dart';
import 'package:provider/provider.dart';

/// PotPlayer-style three-row desktop control bar.
///
/// Row 1 carries the position/duration labels together flush-left as
/// `position / duration` (not split to opposite edges), row 2 the full-width
/// seek bar (no inline time texts — that is what buys the longer, more
/// precise axis), and row 3 the button row with the SAME left/right grouping
/// as the one-line [DesktopControlLayout]: visually only the slider and the
/// time display moved.
class DesktopStackedControlLayout extends HookWidget {
  const DesktopStackedControlLayout({super.key, required this.controls});

  final ControlBarControls controls;

  @override
  Widget build(BuildContext context) {
    final progress = context.select<MediaPlayer,
        ({
          Duration position,
          Duration duration,
        })>(
      (player) => (
        position: player.position,
        duration: player.duration,
      ),
    );

    final color = controls.color;

    // B-scheme dual time (VM-only): the row has horizontal room, so the sub
    // pair rides along in one smaller/dimmer span instead of a second row.
    // Suppressed while the controls target 副音 (bg is a real single file).
    final vmItemRaw = useVmPlaybackStore().select(context, (s) => s.item);
    final bgIsControl = useBackgroundPlaybackStore()
        .select(context, (s) => s.bgOwnsControls);
    final vmSync = useAppStore().select(context, (s) => s.vmDualTimeSync);
    final vmDual = VmDualTime.resolve(
      vmItemForControlTarget(vmItemRaw, bgIsControl: bgIsControl),
      progress.position.inMilliseconds,
      sync: vmSync,
    );
    final bool showVmSub =
        vmDual.showSub && vmDual.segDurMs != null;

    // Same ONE-group contract as the single-line desktop bar (see
    // DesktopControlLayout): group-switch mode replaces the button row with the
    // forced 副音 bar and suppresses the standalone 副音 quick row.
    final bool desktopPhoneMode =
        useAppStore().select(context, (s) => s.desktopCenterZonePhoneMode);
    final PlayerControlGroup group =
        useControlGroupStore().select(context, (s) => s.group);
    final bool floatingDesktop =
        useControlGroupStore().select(context, (s) => s.floatingButtonDesktop);
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Tick isolation: position/duration texts update every tick but carry
        // no extra a11y value beyond the slider (already excluded) — keep the
        // row out of the semantics tree so UIA bridge never serializes its churn.
        // Combined display: "position / duration" together on the left.
        ExcludeSemantics(
          child: Row(
            children: [
              Text.rich(
                TextSpan(
                  text:
                      '${formatDurationToMinutes(Duration(milliseconds: vmDual.displayVirtualMs))} / ${formatDurationToMinutes(progress.duration)}',
                  style: TextStyle(color: color, height: 2),
                  children: [
                    if (showVmSub)
                      TextSpan(
                        text:
                            '  ${formatDurationToMinutes(Duration(milliseconds: vmDual.displayLocalMs))}/${formatDurationToMinutes(Duration(milliseconds: vmDual.segDurMs!))}',
                        style: TextStyle(
                          color: (color ??
                                  Theme.of(context).colorScheme.onSurface)
                              .withValues(alpha: 0.65),
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const Spacer(),
            ],
          ),
        ),
        controls.stackedSlider,
        if (showingBackgroundGroup)
          BackgroundQuickBar(
            axis: Axis.horizontal,
            alignment: MainAxisAlignment.center,
            forceVisible: true,
            color: controls.color,
            overlayColor: controls.overlayColor,
          )
        else ...[
          // 副音 quick row — slider above, button row below (问题 5). Only in
          // legacy mode; group-switch mode owns 副音 through group 2.
          if (showStandaloneQuickBar) controls.backgroundQuickBar,
          // Left/right groups stay two packed units (legacy look); the
          // trailing unit only wraps when the bar is too narrow.
          ControlBarGroupedRow(
            leading: controls.desktopLeftButtons,
            trailing: controls.desktopRightButtons,
          ),
        ],
      ],
    );
  }
}

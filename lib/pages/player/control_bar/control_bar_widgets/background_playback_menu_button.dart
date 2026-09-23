import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/background_playback/actions/background_playback_actions.dart';
import 'package:iris/features/background_playback/background_playback_gate.dart';
import 'package:iris/features/background_playback/model/enum/bg_apply_scope.dart';
import 'package:iris/features/background_playback/model/enum/bg_seek_link.dart';
import 'package:iris/features/background_playback/model/enum/control_target.dart';
import 'package:iris/features/background_playback/store/use_background_playback_store.dart';
import 'package:iris/features/background_playback/view/background_scope_dialog.dart';
import 'package:iris/features/background_playback/view/control_target_indicator.dart';
import 'package:iris/features/background_playback/view/manager/background_mapping_manager_page.dart';
import 'package:iris/features/background_playback/view/media_ratio_dialog.dart';
import 'package:iris/features/control_group/model/enum/player_control_group.dart';
import 'package:iris/features/control_group/store/use_control_group_store.dart';
import 'package:iris/pages/player/control_bar/control_bar_widgets/control_bar_constants.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/utils/platform.dart';
import 'package:iris/widgets/a11y_tooltip.dart';

/// 副音播放 menu on the control bar.
///
/// Mirrors [MoreMenuButton]'s shape (a `PopupMenuButton` with ListTile rows):
/// the master power switch, the per-media apply toggle, the 作用范围 picker,
/// which picture is shown, which runtime the controls drive, the progress lock,
/// the quick-bar switch and the fg/bg volume ratio. The legacy More-menu
/// entries are sealed (see [BackgroundPlaybackGate.legacyMoreMenuEntryEnabled]).
///
/// Rendered only while the feature is available (meta-driven era) —
/// unavailable functionality must never be displayed.
class BackgroundPlaybackMenuButton extends HookWidget {
  const BackgroundPlaybackMenuButton({
    super.key,
    required this.showControl,
    this.color,
    this.overlayColor,
  });

  final VoidCallback showControl;
  final Color? color;
  final WidgetStateProperty<Color?>? overlayColor;

  @override
  Widget build(BuildContext context) {
    if (!BackgroundPlaybackGate.enabled) return const SizedBox.shrink();

    final t = getLocalizations(context);
    final bg = useBackgroundPlaybackStore();
    final enabled = bg.select(context, (s) => s.enabled);
    // bg 未激活不提供 apb 功能 — but only the routing rows (picture/control)
    // are greyed while the gate is closed; 联动/完全独立 and the other saved
    // preferences stay reachable and are applied by the next activation.
    final livePair = bg.select(context, (s) => s.enabled && s.gateOpen);
    final applyScope = bg.select(context, (s) => s.applyScope);
    final displayTarget = bg.select(context, (s) => s.displayTarget);
    final controlTarget = bg.select(context, (s) => s.controlTarget);
    final quickBarEnabled = bg.select(context, (s) => s.quickBarEnabled);
    // The standalone quick bar is phone-hidden, and group 2 owns 副音 there, so
    // its switch is offered only on desktop with the playback group active.
    final PlayerControlGroup controlGroup =
        useControlGroupStore().select(context, (s) => s.group);
    final bool quickBarToggleEnabled =
        !isMobilePlatform && controlGroup != PlayerControlGroup.background;
    final mappingEnabled = bg.select(context, (s) => s.mappingEnabled);
    final seekLink = bg.select(context, (s) => s.seekLink);
    final lockLevel = bg.select(context, (s) => s.lockLevel);
    final keepWarmPlayer = bg.select(context, (s) => s.keepWarmPlayer);
    final fgWindowZoom = bg.select(context, (s) => s.fgWindowZoom);
    final fgWindowPushBg = bg.select(context, (s) => s.fgWindowPushBg);

    final bool bgIsControl =
        livePair && controlTarget == ControlTarget.background;
    final bool bgIsDisplayed =
        livePair && displayTarget == ControlTarget.background;

    return a11yTooltip(
      context: context,
      message: t.bg_menu_tooltip,
      child: PopupMenuButton(
        clipBehavior: Clip.hardEdge,
        style: ButtonStyle(overlayColor: overlayColor),
        constraints: const BoxConstraints(minWidth: kPopupMenuMinWidth),
        icon: Icon(
          Icons.multitrack_audio_rounded,
          size: kIconSizeSecondary,
          color: livePair ? kBackgroundTargetColor : color,
        ),
        itemBuilder: (context) => <PopupMenuEntry<Object>>[
          // 1) 副音功能 on/off — the subsystem switch, distinct from the
          // quick-bar gate (play/stop for the current media) and from the
          // resource kill row below. ON arms the run stopped; OFF fully
          // disables it.
          PopupMenuItem<Object>(
            onTap: () {
              showControl();
              BackgroundPlaybackActions.setFeatureEnabled(!enabled);
            },
            child: ListTile(
              mouseCursor: SystemMouseCursors.click,
              leading: Icon(
                enabled ? Icons.toggle_on_rounded : Icons.toggle_off_rounded,
                size: kMenuTileIconSizeTiny,
                color: enabled ? kBackgroundTargetColor : null,
              ),
              title: Text(enabled ? t.bg_feature_off : t.bg_feature_on),
            ),
          ),
          // 2) 作用范围 (current-only / smart / all) + "跨重启保存".
          PopupMenuItem<Object>(
            onTap: () => showControlForHover(
              context,
              showBackgroundScopeDialog(context),
            ),
            child: ListTile(
              mouseCursor: SystemMouseCursors.click,
              leading:
                  const Icon(Icons.rule_rounded, size: kMenuTileIconSizeTiny),
              title: Text(
                '${t.bg_scope_button}: ${_scopeLabel(applyScope, t)}',
              ),
            ),
          ),
          const PopupMenuDivider(),
          // 4) Which picture is shown (independent of the controls).
          PopupMenuItem<Object>(
            enabled: livePair,
            onTap: livePair
                ? () {
                    showControl();
                    bg.setShowBgVideo(true);
                    bg.cycleDisplayTarget();
                  }
                : null,
            child: ListTile(
              mouseCursor: SystemMouseCursors.click,
              leading: Icon(
                bgIsDisplayed
                    ? Icons.smart_display_rounded
                    : Icons.smart_display_outlined,
                size: kMenuTileIconSizeTiny,
              ),
              title: Text(
                bgIsDisplayed ? t.bg_display_to_fg : t.bg_display_to_bg,
              ),
            ),
          ),
          // 5) Which runtime the shared controls drive.
          PopupMenuItem<Object>(
            enabled: livePair,
            onTap: livePair
                ? () {
                    showControl();
                    bg.cycleTarget();
                  }
                : null,
            child: ListTile(
              mouseCursor: SystemMouseCursors.click,
              leading: Icon(
                bgIsControl
                    ? Icons.settings_remote_rounded
                    : Icons.settings_input_component_rounded,
                size: kMenuTileIconSizeTiny,
                color: bgIsControl ? kBackgroundTargetColor : null,
              ),
              title: Text(
                bgIsControl ? t.bg_control_to_fg : t.bg_control_to_bg,
              ),
            ),
          ),
          const PopupMenuDivider(),
          // 6) 联动 (A) / 完全独立 (B) — mutually exclusive. A shows the current
          // sub-mode and cycles it on tap (full ↔ play/pause only); B unlocks.
          // These are saved preferences (同步方式/联动等级), so they stay
          // reachable while the gate is closed and are applied by the next
          // activation — unlike the routing rows above.
          PopupMenuItem<Object>(
            onTap: () {
              showControl();
              if (seekLink != BgSeekLink.linked) {
                bg.setSeekLink(BgSeekLink.linked);
              } else {
                bg.setLockLevel(
                  lockLevel == BgLockLevel.high
                      ? BgLockLevel.low
                      : BgLockLevel.high,
                );
              }
            },
            child: ListTile(
              mouseCursor: SystemMouseCursors.click,
              leading: Icon(
                (seekLink == BgSeekLink.linked &&
                        lockLevel == BgLockLevel.low)
                    ? Icons.pause_circle_outline_rounded
                    : Icons.sync_rounded,
                size: kMenuTileIconSizeTiny,
                color: seekLink == BgSeekLink.linked
                    ? kBackgroundTargetColor
                    : null,
              ),
              title: Text(
                '${t.bg_seek_link}: '
                '${seekLink == BgSeekLink.linked ? _lockLevelLabel(lockLevel, t) : t.bg_seek_independent}',
              ),
            ),
          ),
          PopupMenuItem<Object>(
            onTap: () {
              showControl();
              bg.setSeekLink(BgSeekLink.independent);
            },
            child: ListTile(
              mouseCursor: SystemMouseCursors.click,
              leading: Icon(
                Icons.link_off_rounded,
                size: kMenuTileIconSizeTiny,
                color: seekLink == BgSeekLink.independent
                    ? kBackgroundTargetColor
                    : null,
              ),
              title: Text(t.bg_seek_independent),
            ),
          ),
          // 7) 快速控制栏 on/off — kept here rather than in the quick bar
          // itself, which is where scarce horizontal space lives. Disabled
          // while the bottom group 2 owns 副音 (and on phones, where the
          // standalone bar no longer exists).
          PopupMenuItem<Object>(
            enabled: quickBarToggleEnabled,
            onTap: quickBarToggleEnabled
                ? () {
                    showControl();
                    bg.setQuickBarEnabled(!quickBarEnabled);
                  }
                : null,
            child: ListTile(
              enabled: quickBarToggleEnabled,
              mouseCursor: quickBarToggleEnabled
                  ? SystemMouseCursors.click
                  : SystemMouseCursors.basic,
              leading: Icon(
                quickBarEnabled
                    ? Icons.view_column_rounded
                    : Icons.view_column_outlined,
                size: kMenuTileIconSizeTiny,
              ),
              title: Text(t.bg_quick_bar),
              trailing: quickBarEnabled
                  ? Icon(Icons.check_rounded,
                      size: 18, color: Theme.of(context).colorScheme.primary)
                  : null,
            ),
          ),
          const PopupMenuDivider(),
          // 8) fg/bg volume ratio.
          PopupMenuItem<Object>(
            onTap: () => showControlForHover(
              context,
              showMediaRatioDialog(context),
            ),
            child: ListTile(
              mouseCursor: SystemMouseCursors.click,
              leading:
                  const Icon(Icons.tune_rounded, size: kMenuTileIconSizeTiny),
              title: Text(t.bg_volume_ratio),
            ),
          ),
          // 8b) 映射管理 — the two-level saved-timeline manager (list → axis).
          PopupMenuItem<Object>(
            onTap: () => showControlForHover(
              context,
              showBackgroundMappingManager(context),
            ),
            child: ListTile(
              mouseCursor: SystemMouseCursors.click,
              leading: const Icon(Icons.playlist_play_rounded,
                  size: kMenuTileIconSizeTiny),
              title: Text(t.bg_mapping_manager_title),
            ),
          ),
          // 8c) 自动使用已保存的映射 — default ON. Off makes 副音 ignore every
          // saved timeline and play naturally.
          PopupMenuItem<Object>(
            onTap: () {
              showControl();
              bg.setMappingEnabled(!mappingEnabled);
            },
            child: ListTile(
              mouseCursor: SystemMouseCursors.click,
              leading: Icon(
                mappingEnabled
                    ? Icons.auto_awesome_rounded
                    : Icons.auto_awesome_outlined,
                size: kMenuTileIconSizeTiny,
              ),
              title: Text(t.set_bg_use_saved_mapping),
              trailing: mappingEnabled
                  ? Icon(Icons.check_rounded,
                      size: 18, color: Theme.of(context).colorScheme.primary)
                  : null,
            ),
          ),
          // 8d) APB 前景缩放倍率 — cycles through presets. A preference, so it
          // stays reachable while the gate is closed; the align editor reads it.
          PopupMenuItem<Object>(
            onTap: () {
              showControl();
              bg.setFgWindowZoom(_nextFgZoom(fgWindowZoom));
            },
            child: ListTile(
              mouseCursor: SystemMouseCursors.click,
              leading: const Icon(Icons.zoom_out_map_rounded,
                  size: kMenuTileIconSizeTiny),
              title: Text('${t.set_bg_fg_window_zoom}: $fgWindowZoom×'),
            ),
          ),
          // 8e) q 推动副音映射 — what the q handle does at the A/B boundary.
          PopupMenuItem<Object>(
            onTap: () {
              showControl();
              bg.setFgWindowPushBg(!fgWindowPushBg);
            },
            child: ListTile(
              mouseCursor: SystemMouseCursors.click,
              leading: Icon(
                fgWindowPushBg
                    ? Icons.push_pin_rounded
                    : Icons.push_pin_outlined,
                size: kMenuTileIconSizeTiny,
              ),
              title: Text(t.set_bg_fg_window_push_bg),
              trailing: fgWindowPushBg
                  ? Icon(Icons.check_rounded,
                      size: 18, color: Theme.of(context).colorScheme.primary)
                  : null,
            ),
          ),
          // 9) 彻底关闭后台 / 重新开启副音支持 — the former power switch's
          // resource half. OFF stops the run AND drops the warm engine; ON
          // rebuilds it without touching what is playing.
          PopupMenuItem<Object>(
            onTap: () {
              showControl();
              if (keepWarmPlayer) {
                BackgroundPlaybackActions.releaseResources();
              } else {
                BackgroundPlaybackActions.reenableSupport();
              }
            },
            child: ListTile(
              mouseCursor: SystemMouseCursors.click,
              leading: Icon(
                keepWarmPlayer
                    ? Icons.power_settings_new_rounded
                    : Icons.restart_alt_rounded,
                size: kMenuTileIconSizeTiny,
              ),
              title: Text(
                keepWarmPlayer ? t.bg_release_resources : t.bg_reenable_support,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> showControlForHover(
      BuildContext context, Future<void> run) async {
    showControl();
    await run;
    showControl();
  }
}

/// Preset multipliers the 副音 menu's APB foreground-zoom row cycles through.
const List<double> _kFgZoomPresets = <double>[1.0, 1.5, 2.0, 3.0, 5.0, 10.0];

/// Next preset above [current] (wrapping to the first), so one tap on the menu
/// row steps the multiplier without opening another dialog.
double _nextFgZoom(double current) {
  for (final double z in _kFgZoomPresets) {
    if (z > current + 0.001) return z;
  }
  return _kFgZoomPresets.first;
}

String _lockLevelLabel(BgLockLevel level, AppLocalizations t) =>
    switch (level) {
      BgLockLevel.high => t.bg_lock_level_high,
      BgLockLevel.low => t.bg_lock_level_low,
    };

String _scopeLabel(BgApplyScope scope, AppLocalizations t) => switch (scope) {
      BgApplyScope.currentOnly => t.bg_scope_current_only,
      BgApplyScope.smart => t.bg_scope_smart,
      BgApplyScope.all => t.bg_scope_all,
    };

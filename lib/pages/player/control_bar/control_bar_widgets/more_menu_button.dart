import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/background_playback/actions/background_playback_actions.dart';
import 'package:iris/features/background_playback/background_playback_gate.dart';
import 'package:iris/features/background_playback/store/use_background_playback_store.dart';
import 'package:iris/features/phone/one_handed_scrubber/controller/phone_scrubber_slot.dart';
import 'package:iris/features/meta_settings/meta_settings_module.dart';
import 'package:iris/features/playback_tools/view/screenshot_capture_flow.dart';
import 'package:iris/features/playback_tools/store/playback_tools_store.dart';
import 'package:iris/features/playback_tools/view/screenshot_feedback.dart';
import 'package:iris/features/scenario_playback/actions/scenario_playback_common.dart';
import 'package:iris/features/scenario_playback/scan/commands/scenario_source_scan_command.dart';
import 'package:iris/features/scenario_playback/store/use_playback_scenario_store.dart';
import 'package:iris/features/tag_play/commands/tag_play_actions.dart';
import 'package:iris/features/virtual_media/commands/vm_actions.dart';
import 'package:iris/features/virtual_media/vm_gate.dart';
import 'package:iris/features/windows/desktop_keyboard/controller/resolve_keyboard_scheme.dart';
import 'package:iris/features/windows/desktop_keyboard/view/show_jump_to_time_dialog.dart';
import 'package:iris/features/windows/desktop_keyboard/view/shortcut_hints.dart';
import 'package:iris/features/windows/desktop_keyboard/controller/resolve_keybinds.dart';
import 'package:iris/features/windows/desktop_keyboard/model/keybind_codec.dart';
import 'package:iris/features/windows/desktop_keyboard/model/potplayer_action.dart';
import 'package:iris/globals.dart' show moreMenuKeyNotifier;
import 'package:iris/hooks/use_published_global_key.dart';
import 'package:iris/models/player.dart';
import 'package:iris/models/storages/local.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/models/store/phone_landscape_slider_type_helper.dart';
import 'package:iris/pages/player/control_bar/control_bar_widgets/control_bar_constants.dart';
import 'package:iris/pages/player/control_bar/control_bar_widgets/seek_step_popover.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_player_ui_store.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/utils/platform.dart';
import 'package:iris/widgets/bottom_sheets/show_open_link_bottom_sheet.dart';
import 'package:iris/widgets/controls/circle_slider_panel_width_control.dart';
import 'package:iris/widgets/controls/circle_slider_scale_control.dart';
import 'package:iris/widgets/dialogs/show_open_link_dialog.dart';
import 'package:iris/widgets/dialogs/show_control_group_floating_dialog.dart';
import 'package:iris/widgets/dialogs/show_slider_type_dialog.dart';
import 'package:iris/widgets/dialogs/show_rate_dialog.dart';
import 'package:iris/widgets/dialogs/show_snake_fine_window_dialog.dart';
import 'package:iris/widgets/popup.dart';
import 'package:iris/widgets/popups/history.dart';
import 'package:iris/widgets/popups/settings/settings.dart';
import 'package:iris/widgets/popups/track/subtitle_and_audio_track.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

class MoreMenuButton extends HookWidget {
  const MoreMenuButton({
    super.key,
    required this.showControl,
    required this.showControlForHover,
    this.color,
    this.overlayColor,
  });

  final void Function() showControl;
  final Future<void> Function(Future<void>) showControlForHover;
  final Color? color;
  final WidgetStateProperty<Color?>? overlayColor;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    // Per-mount key published for the keyboard shortcuts (see
    // `usePublishedGlobalKey`): never a shared object.
    final GlobalKey<PopupMenuButtonState> menuKey =
        usePublishedGlobalKey(moreMenuKeyNotifier);

    final rate = useAppStore().select(context, (s) => s.rate);
    final runtimeOrientation = useAppStore().select(context, (s) => s.runtimeOrientation);
    final popupDirection = useAppStore().select(context, (s) => s.defaultPopupDirection);
    // snakeFineSec retained as dead state (fine-tune axis retired); menu entry removed per spec.
    // ignore: unused_local_variable
    final int snakeFineSec = useAppStore().select(context, (s) => s.snakeFineWindowSeconds);
    final int seekStepSec = useAppStore().select(context, (s) => s.seekStepSeconds);

    final width = MediaQuery.sizeOf(context).width;
    final realOrientation = MediaQuery.of(context).orientation;

    final bool isLandscape = () {
      switch (runtimeOrientation) {
        case ScreenOrientation.landscape:
          return true;
        case ScreenOrientation.portrait:
          return false;
        case ScreenOrientation.device:
          return realOrientation == Orientation.landscape;
      }
    }();

    final PhoneLandscapeUseMode phoneUseMode =
        useAppStore().select(context, (s) => s.phoneLandscapeUseMode);
    final PhoneOneHandedScrubberKind scrubberKind =
        useAppStore().select(context, (s) => s.phoneOneHandedScrubberKind);
    final bool metaSettingsOn =
        useAppStore().select(context, (s) => s.useMetadataSettings);
    // Menu shortcut hints follow the EFFECTIVE keyboard scheme so the labels
    // never contradict the live bindings (D10).
    final effectiveScheme = resolveKeyboardScheme(
      stored: useAppStore().select(context, (s) => s.keyboardShortcutScheme),
      metadataEnabled: metaSettingsOn && MetaSettingsModule.ready,
    );
    final bool isPortraitHidden = isMobilePlatform && !isLandscape;
    final bool shouldShowSidePanelEntry = !isPortraitHidden;
    final bool oneHandedActive =
        (isDesktop || (isMobilePlatform && isLandscape)) &&
            phoneUseMode.usesOneHandedControls;
    final PhoneScrubberSlot scrubberSlot = resolveScrubberSlot(
      kind: scrubberKind,
      metadataEnabled: metaSettingsOn,
    );
    // Ring dial styling only matters when the ring dial itself renders.
    final bool showRingDialItem = oneHandedActive &&
        scrubberSlot == PhoneScrubberSlot.oneHanded &&
        scrubberKind == PhoneOneHandedScrubberKind.dial;

    // Playback-tools state must be read HERE (build phase): itemBuilder runs
    // during the tap gesture, where context.select() asserts and kills the
    // whole menu. Same precomputed-args convention as every other item below.
    final bool frameToolsVisible =
        usePlaybackToolsStore().select(context, (s) => s.frameToolsVisible);
    // Bottom control-group switch button: available where a second group is
    // (phones, desktop phone-mode). State read in build — see note above.
    final bool cgPhoneMode = useAppStore()
        .select(context, (s) => isMobilePlatform || s.desktopCenterZonePhoneMode);

    // 副音 float-panel visibility toggle (shown only while 副音 runs).
    final bgStore = useBackgroundPlaybackStore();
    final bool bgEnabled = bgStore.select(context, (s) => s.enabled);
    final bool bgPanelVisible = bgStore.select(context, (s) => s.bgPanelVisible);

    // Keybind-aware hints: precompute in build so itemBuilder stays select-free.
    final String keybindJson = useAppStore().select(context, (s) => s.keybindOverridesJson);
    String? hintForTarget(DesktopShortcutHintTarget target) {
      final String? base = shortcutHintLabel(target, effectiveScheme);
      if (effectiveScheme != KeyboardShortcutScheme.potplayer ||
          !metaSettingsOn ||
          !MetaSettingsModule.ready) return base;
      final PotPlayerAction? action = switch (target) {
        DesktopShortcutHintTarget.openFile => PotPlayerAction.openFile,
        DesktopShortcutHintTarget.openLink => PotPlayerAction.openLink,
        DesktopShortcutHintTarget.history => PotPlayerAction.historyPanel,
        DesktopShortcutHintTarget.settings => PotPlayerAction.settings,
        DesktopShortcutHintTarget.exit => PotPlayerAction.exitApp,
        DesktopShortcutHintTarget.jumpToTime => PotPlayerAction.jumpToTime,
      };
      if (action == null) return base;
      final overrides = KeybindCodec.decodeOverrides(keybindJson);
      if (!overrides.containsKey(action.name)) return base;
      final grouped = groupedEffectiveCombos(overrides: overrides, metadataEnabled: true);
      final combos = grouped[action];
      if (combos == null || combos.isEmpty) return null;
      return combos.map(KeybindCodec.labelFor).join(' / ');
    }

    final String? openFileHint = hintForTarget(DesktopShortcutHintTarget.openFile);
    final String? openLinkHint = hintForTarget(DesktopShortcutHintTarget.openLink);
    final String? historyHint = hintForTarget(DesktopShortcutHintTarget.history);
    final String? settingsHint = hintForTarget(DesktopShortcutHintTarget.settings);
    final String? exitHint = hintForTarget(DesktopShortcutHintTarget.exit);
    final String? jumpHint = hintForTarget(DesktopShortcutHintTarget.jumpToTime);
    final String? subtitleHint = shortcutHintLabelFor(ShortcutHintKind.subtitleAudio, effectiveScheme);

    final double sidewayW = useAppStore().select(context, (s) => s.sidewayPanelWidthPct);
    final double sidewayH = useAppStore().select(context, (s) => s.sidewayPanelHeightPct);
    final double sidewayWpx = useAppStore().select(context, (s) => s.sidewayPanelWidthPx);
    final double sidewayHpx = useAppStore().select(context, (s) => s.sidewayPanelHeightPx);
    // Desktop sizes the panel in absolute px (phone uses screen %); show what
    // is actually applied instead of always the phone percentages.
    final String sidePanelTitle = isDesktop
        ? t.menu_side_panel_px(
            sidewayWpx.toStringAsFixed(0), sidewayHpx.toStringAsFixed(0))
        : t.menu_side_panel(
            sidewayW.toStringAsFixed(0), sidewayH.toStringAsFixed(0));
    final bool showSidewayPanelItems = oneHandedActive;

    // Scenario-driven playback only: the current workspace scenario (the
    // active independent entry's own workspace, else SystemPlaying) is the
    // scan target. Read once here so itemBuilder stays select-free.
    final bool scenarioMode = useAppStore().select(
      context,
      (s) => !s.useLegacyStoragePersistence && s.useScenarioDrivenPlayback,
    );
    final String? scanScenarioId = scenarioMode
        ? currentPlaybackWorkspace(usePlaybackScenarioStore())?.id
        : null;

    return PopupMenuButton(
      key: menuKey,
      icon: Icon(Icons.more_vert_rounded, size: kIconSizeSecondary, color: color),
      style: ButtonStyle(overlayColor: overlayColor),
      clipBehavior: Clip.hardEdge,
      constraints: const BoxConstraints(minWidth: kPopupMenuMinWidth),
      itemBuilder: (context) => [
        _openFileItemWithHint(context, t, openFileHint),
        _openLinkItemWithHint(context, t, openLinkHint),
        _jumpToTimeItemWithHint(context, t, jumpHint),
        // Seek step moved here from every control bar (sub_media §3): the
        // adjuster is a rarely-used setting, so it left the primary bar.
        _seekStepItem(context, t, seekStepSec),
        _tagPlayItem(context, t),
        if (scanScenarioId != null)
          _scanSourcesItem(context, t, scanScenarioId),
        // DEPRECATED (sub_media §2): the legacy More-menu 副音 entries are
        // sealed behind a permanently-false flag. Code kept for rollback;
        // the control-bar 副音 menu now owns these intents.
        if (BackgroundPlaybackGate.legacyMoreMenuEntryEnabled) ...[
          if (bgEnabled && BackgroundPlaybackGate.enabled)
            _bgPanelItem(context, t,
                visible: bgPanelVisible,
                onToggle: () => bgStore.setPanelVisible(!bgPanelVisible)),
          _backgroundPlaybackItem(context, t),
        ],
        // Legacy VirtualMedia sheet sealed (VirtualMediaGate.legacySheetEnabled
        // is permanently false): rule CRUD lives in meta-settings, playback
        // stays unaware single-video. Row hidden, definition kept as dead code.
        if (VirtualMediaGate.legacySheetEnabled) _virtualMediaItem(context, t),
        if (width < kRateTileBreakpoints) _rateItem(context, t, rate),
        if (shouldShowSidePanelEntry)
          _unifiedSidePanelItem(context, t, sidePanelTitle),
        // Fine-tune range retired — dial axis strip now mirrors global seek step.
        // _snakeFineItem retained as dead code (showSnakeFineWindowDialog still exists).
        // Phone-only playback tools (float panel + capture).
        if (isMobilePlatform) ...[
          _frameToolsItem(context, t, frameToolsVisible),
          _screenshotItem(context, t),
        ],
        // Floating bottom-group switch button (phone / desktop phone-mode).
        if (cgPhoneMode) _controlGroupItem(context, t),
        // Subtitle & audio tracks — moved from control bar (now seek step) to More.
        // Industry standard grouping: playback tracks sit directly above History
        // (before system entries Settings/Exit), so they remain discoverable
        // without cluttering the main bar.
        _subtitleItemWithHint(context, t, popupDirection, subtitleHint),
        _historyItemWithHint(context, t, popupDirection, historyHint),
        _settingsItemWithHint(context, t, popupDirection, settingsHint),
        _exitItemWithHint(context, t, exitHint),
        if (isMobilePlatform) _gestureTipsItem(context, t),
      ],
    );
  }

  /// Seek-step adjuster (sub_media §3) — opens the same transparent popover
  /// that used to hang off the control bar's seek-step button.
  PopupMenuItem _seekStepItem(BuildContext context, t, int sec) {
    return PopupMenuItem(
      child: ListTile(
        mouseCursor: SystemMouseCursors.click,
        leading: const Icon(Icons.update, size: kMenuTileIconSizeTiny),
        title: Text('${t.menu_seek_step}: ${sec}s'),
      ),
      onTap: () => showControlForHover(showSeekStepPopover(context)),
    );
  }

  /// Tag play sheet — same feature as the region-gesture double-tap entry.
  PopupMenuItem _tagPlayItem(BuildContext context, t) {
    return PopupMenuItem(
      child: ListTile(
        mouseCursor: SystemMouseCursors.click,
        leading:
            const Icon(Icons.style_rounded, size: kMenuTileIconSizeTiny),
        title: Text(t.menu_tag_play),
      ),
      onTap: () {
        showControlForHover(openTagPlaySheet(context));
      },
    );
  }

  /// 扫描更新源数据 — re-scans the current workspace scenario's source
  /// storages and refreshes the resolved play queue. Greyed while every
  /// configured storage is known-unreachable.
  PopupMenuItem _scanSourcesItem(
      BuildContext context, t, String scenarioId) {
    final enabled = ScenarioSourceScanCommand.isEnabled();
    return PopupMenuItem(
      enabled: enabled,
      child: ListTile(
        enabled: enabled,
        mouseCursor: SystemMouseCursors.click,
        leading: Icon(
          Icons.autorenew_rounded,
          size: kMenuTileIconSizeTiny,
          color: enabled ? null : Theme.of(context).disabledColor,
        ),
        title: Text(t.scn_scan_sources),
      ),
      onTap: () async {
        showControl();
        final navigator = Navigator.of(context, rootNavigator: true);
        await ScenarioSourceScanCommand.run(
          // ignore: use_build_context_synchronously
          context,
          scenarioId: scenarioId,
        );
        // The scan may have opened dialogs on the root navigator; keep the
        // controls restored for when they dismiss.
        if (navigator.mounted) showControl();
      },
    );
  }

  /// 副音播放 — launches the independent background playback engine (gate
  /// OFF → explanatory dialog, same pattern as the tag play sheet).
  PopupMenuItem _backgroundPlaybackItem(BuildContext context, t) {
    return PopupMenuItem(
      child: ListTile(
        mouseCursor: SystemMouseCursors.click,
        leading:
            const Icon(Icons.multitrack_audio_rounded, size: kMenuTileIconSizeTiny),
        title: Text(t.menu_background_playback),
      ),
      onTap: () {
        showControlForHover(BackgroundPlaybackActions.open(context));
      },
    );
  }

  /// 副音 float-panel show/hide (collapse pill state) while 副音 is running.
  /// Hiding the panel never stops playback — the X on the panel does.
  PopupMenuItem _bgPanelItem(BuildContext context, t,
      {required bool visible, required VoidCallback onToggle}) {
    return PopupMenuItem(
      child: ListTile(
        mouseCursor: SystemMouseCursors.click,
        leading: Icon(
          visible
              ? Icons.picture_in_picture_alt_rounded
              : Icons.picture_in_picture_alt_outlined,
          size: kMenuTileIconSizeTiny,
        ),
        title: Text(t.bg_panel_toggle),
        trailing: visible
            ? Icon(Icons.check_rounded,
                size: 18, color: Theme.of(context).colorScheme.primary)
            : null,
      ),
      onTap: onToggle,
    );
  }

  /// Virtual Media sheet — rules → virtual sequential items (spec v2).
  PopupMenuItem _virtualMediaItem(BuildContext context, t) {
    return PopupMenuItem(
      child: ListTile(
        mouseCursor: SystemMouseCursors.click,
        leading:
            const Icon(Icons.auto_awesome_motion_rounded, size: kMenuTileIconSizeTiny),
        title: Text(t.menu_virtual_media),
      ),
      onTap: () {
        showControlForHover(openVirtualMediaSheet(context));
      },
    );
  }

  PopupMenuItem _openFileItem(
      BuildContext context, t, KeyboardShortcutScheme scheme) {    return PopupMenuItem(
      child: ListTile(
        mouseCursor: SystemMouseCursors.click,
        leading: const Icon(Icons.file_open_rounded, size: kMenuTileIconSizeTiny),
        title: Text(t.open_file),
        trailing: _hintText(context, DesktopShortcutHintTarget.openFile, scheme),
      ),
      onTap: () async {
        showControl();
        if (isAndroid) {
          await pickContentFile();
        } else {
          await pickLocalFile();
        }
        showControl();
      },
    );
  }

  Widget? _hintText(
      BuildContext context, DesktopShortcutHintTarget target, KeyboardShortcutScheme scheme) {
    final String? label = shortcutHintLabel(target, scheme);
    if (label == null) return null;
    return Text(
      label,
      style: TextStyle(
          fontSize: kMenuTextFontSizeShortcut, color: Theme.of(context).dividerColor),
    );
  }

  Widget? _hintFromLabel(BuildContext context, String? label) {
    if (label == null) return null;
    return Text(
      label,
      style: TextStyle(fontSize: kMenuTextFontSizeShortcut, color: Theme.of(context).dividerColor),
    );
  }

  /// Jump-to-position entry (PotPlayer `G` parity; visible on all platforms).
  PopupMenuItem _jumpToTimeItem(
      BuildContext context, t, KeyboardShortcutScheme scheme) {
    return PopupMenuItem(
      child: ListTile(
        mouseCursor: SystemMouseCursors.click,
        leading: const Icon(Icons.schedule_rounded, size: kMenuTileIconSizeTiny),
        title: Text(t.menu_jump_to_time),
        trailing: _hintText(context, DesktopShortcutHintTarget.jumpToTime, scheme),
      ),
      onTap: () => showControlForHover(
          showJumpToTimeDialog(context, context.read<MediaPlayer>())),
    );
  }

  PopupMenuItem _openLinkItem(
      BuildContext context, t, KeyboardShortcutScheme scheme) {
    return PopupMenuItem(
      child: ListTile(
        mouseCursor: SystemMouseCursors.click,
        leading: const Icon(Icons.file_present_rounded, size: kMenuTileIconSizeTiny),
        title: Text(t.open_link),
        trailing: _hintText(context, DesktopShortcutHintTarget.openLink, scheme),
      ),
      onTap: () async {
        isDesktop ? await showOpenLinkDialog(context) : await showOpenLinkBottomSheet(context);
        showControl();
      },
    );
  }

  PopupMenuItem _rateItem(BuildContext context, t, double rate) {
    return PopupMenuItem(
      child: ListTile(
        mouseCursor: SystemMouseCursors.click,
        leading: const Icon(Icons.speed_rounded, size: kMenuTileIconSize),
        title: Text('${t.playback_speed}: ${rate}X'),
      ),
      onTap: () => showControlForHover(showRatePickerDialog(context)),
    );
  }

  PopupMenuItem _circleSliderPercentItem(BuildContext context, t, int percent) {
    return PopupMenuItem(
      child: ListTile(
        mouseCursor: SystemMouseCursors.click,
        leading: const Icon(Icons.space_bar, size: kMenuTileIconSize),
        title: Text('${t.circle_slider_landscape_percent}: $percent%'),
      ),
      onTap: () => showControlForHover(
        showCircleSliderLandscapePercentControlPopover(context, showControl),
      ),
    );
  }

  PopupMenuItem _historyItem(BuildContext context, t, PopupDirection popupDirec,
      KeyboardShortcutScheme scheme) {
    return PopupMenuItem(
      child: ListTile(
        mouseCursor: SystemMouseCursors.click,
        leading: const Icon(Icons.history_rounded, size: kMenuTileIconSize),
        title: Text(t.history),
        trailing: _hintText(context, DesktopShortcutHintTarget.history, scheme),
      ),
      onTap: () => showControlForHover(
        showPopup(
          context: context,
          child: const History(),
          direction: popupDirec,
        ),
      ),
    );
  }

  PopupMenuItem _settingsItem(BuildContext context, t, PopupDirection popupDirec,
      KeyboardShortcutScheme scheme) {
    return PopupMenuItem(
      child: ListTile(
        mouseCursor: SystemMouseCursors.click,
        leading: const Icon(Icons.settings_rounded, size: kMenuTileIconSize),
        title: Text(t.settings),
        trailing: _hintText(context, DesktopShortcutHintTarget.settings, scheme),
      ),
      onTap: () => showControlForHover(
        showPopup(
          context: context,
          child: const Settings(),
          direction: popupDirec,
        ),
      ),
    );
  }

  PopupMenuItem _exitItem(BuildContext context, t, KeyboardShortcutScheme scheme) {
    return PopupMenuItem(
      child: ListTile(
        mouseCursor: SystemMouseCursors.click,
        leading: const Icon(Icons.exit_to_app_rounded, size: kMenuTileIconSize),
        title: Text(t.exit),
        trailing: _hintText(context, DesktopShortcutHintTarget.exit, scheme),
      ),
      onTap: () async {
        await context.read<MediaPlayer>().saveProgress();
        if (isDesktop) {
          windowManager.close();
        } else {
          SystemNavigator.pop();
          exit(0);
        }
      },
    );
  }

  // Hint-precomputed variants (build-phase labels; itemBuilder stays select-free).
  PopupMenuItem _openFileItemWithHint(BuildContext context, t, String? hint) {
    return PopupMenuItem(
      child: ListTile(
        mouseCursor: SystemMouseCursors.click,
        leading: const Icon(Icons.file_open_rounded, size: kMenuTileIconSizeTiny),
        title: Text(t.open_file),
        trailing: _hintFromLabel(context, hint),
      ),
      onTap: () async {
        showControl();
        if (isAndroid) {
          await pickContentFile();
        } else {
          await pickLocalFile();
        }
        showControl();
      },
    );
  }

  PopupMenuItem _openLinkItemWithHint(BuildContext context, t, String? hint) {
    return PopupMenuItem(
      child: ListTile(
        mouseCursor: SystemMouseCursors.click,
        leading: const Icon(Icons.file_present_rounded, size: kMenuTileIconSizeTiny),
        title: Text(t.open_link),
        trailing: _hintFromLabel(context, hint),
      ),
      onTap: () async {
        isDesktop ? await showOpenLinkDialog(context) : await showOpenLinkBottomSheet(context);
        showControl();
      },
    );
  }

  PopupMenuItem _jumpToTimeItemWithHint(
      BuildContext context, t, String? hint) {
    return PopupMenuItem(
      child: ListTile(
        mouseCursor: SystemMouseCursors.click,
        leading: const Icon(Icons.schedule_rounded, size: kMenuTileIconSizeTiny),
        title: Text(t.menu_jump_to_time),
        trailing: _hintFromLabel(context, hint),
      ),
      onTap: () => showControlForHover(showJumpToTimeDialog(context, context.read<MediaPlayer>())),
    );
  }

  PopupMenuItem _historyItemWithHint(BuildContext context, t, PopupDirection dir, String? hint) {
    return PopupMenuItem(
      child: ListTile(
        mouseCursor: SystemMouseCursors.click,
        leading: const Icon(Icons.history_rounded, size: kMenuTileIconSize),
        title: Text(t.history),
        trailing: _hintFromLabel(context, hint),
      ),
      onTap: () => showControlForHover(showPopup(context: context, child: const History(), direction: dir)),
    );
  }

  PopupMenuItem _settingsItemWithHint(BuildContext context, t, PopupDirection dir, String? hint) {
    return PopupMenuItem(
      child: ListTile(
        mouseCursor: SystemMouseCursors.click,
        leading: const Icon(Icons.settings_rounded, size: kMenuTileIconSize),
        title: Text(t.settings),
        trailing: _hintFromLabel(context, hint),
      ),
      onTap: () => showControlForHover(showPopup(context: context, child: const Settings(), direction: dir)),
    );
  }

  PopupMenuItem _subtitleItemWithHint(BuildContext context, t, PopupDirection dir, String? hint) {
    return PopupMenuItem(
      child: ListTile(
        mouseCursor: SystemMouseCursors.click,
        leading: const Icon(Icons.subtitles_rounded, size: kMenuTileIconSize),
        title: Text(t.subtitle_and_audio_track),
        trailing: _hintFromLabel(context, hint),
      ),
      onTap: () => showControlForHover(showPopup(
        context: context,
        child: Provider<MediaPlayer>.value(
          value: context.read<MediaPlayer>(),
          child: const SubtitleAndAudioTrack(),
        ),
        direction: dir,
      )),
    );
  }

  PopupMenuItem _exitItemWithHint(BuildContext context, t, String? hint) {
    return PopupMenuItem(
      child: ListTile(
        mouseCursor: SystemMouseCursors.click,
        leading: const Icon(Icons.exit_to_app_rounded, size: kMenuTileIconSize),
        title: Text(t.exit),
        trailing: _hintFromLabel(context, hint),
      ),
      onTap: () async {
        await context.read<MediaPlayer>().saveProgress();
        if (isDesktop) {
          windowManager.close();
        } else {
          SystemNavigator.pop();
          exit(0);
        }
      },
    );
  }

  PopupMenuItem _gestureTipsItem(BuildContext context, t) {
    return PopupMenuItem(
      child: ListTile(
        mouseCursor: SystemMouseCursors.click,
        leading: const Icon(Icons.touch_app_rounded, size: kMenuTileIconSize),
        title: Text(t.show_gesture_overlay),
      ),
      onTap: () => usePlayerUiStore().updateIsShowGestureTips(true),
    );
  }

  PopupMenuItem _circleSliderScaleItem(BuildContext context, t, double scale) {
    final percent = (scale * 100).round();

    return PopupMenuItem(
      child: ListTile(
        mouseCursor: SystemMouseCursors.click,
        leading: Icon(Icons.expand, size: kMenuTileIconSize),
        title: Text('${t.circle_slider_scale}: $percent%'),
      ),
      onTap: () => showControlForHover(
        showCircleSliderScaleControlPopover(context, showControl),
      ),
    );
  }

  PopupMenuItem _unifiedSidePanelItem(
    BuildContext context,
    t,
    String title,
  ) {
    return PopupMenuItem(
      child: ListTile(
        mouseCursor: SystemMouseCursors.click,
        leading: const Icon(Icons.aspect_ratio_rounded, size: kMenuTileIconSize),
        title: Text(title),
        subtitle: Text(t.menu_side_panel_desc),
      ),
      onTap: () => showControlForHover(showSliderTypeDialog(context)),
    );
  }

  PopupMenuItem _snakeFineItem(BuildContext context, t, int sec) {
    return PopupMenuItem(
      child: ListTile(
        mouseCursor: SystemMouseCursors.click,
        leading: const Icon(Icons.tune_rounded, size: kMenuTileIconSize),
        title: Text(t.menu_fine_tune(sec)),
      ),
      onTap: () => showControlForHover(showSnakeFineWindowDialog(context)),
    );
  }

  /// Frame-tools float panel toggle — the phone vehicle for frame stepping
  /// (per decision: not in the control bar, not a gesture action).
  PopupMenuItem _frameToolsItem(BuildContext context, t, bool active) {
    return PopupMenuItem(
      child: ListTile(
        mouseCursor: SystemMouseCursors.click,
        leading: const Icon(Icons.slow_motion_video_rounded,
            size: kMenuTileIconSize),
        title: Text(t.menu_frame_tools),
        trailing: active
            ? Icon(Icons.check_rounded, size: kMenuTileIconSize)
            : null,
      ),
      onTap: () {
        showControl();
        usePlaybackToolsStore().toggleFrameTools();
      },
    );
  }

  /// Direct screenshot entry sharing the float-panel shutter logic.
  PopupMenuItem _screenshotItem(BuildContext context, t) {
    return PopupMenuItem(
      child: ListTile(
        mouseCursor: SystemMouseCursors.click,
        leading:
            const Icon(Icons.photo_camera_rounded, size: kMenuTileIconSize),
        title: Text(t.menu_screenshot),
      ),
      onTap: () async {
        showControl();
        // Navigator captured BEFORE the await so the feedback dialog shows
        // even after the popup menu unmounts.
        final navigator = Navigator.of(context, rootNavigator: true);
        final t = getLocalizations(context);
        final result = await runScreenshotCapture(
          navigator: navigator,
          player: context.read<MediaPlayer>(),
          savingLabel: t.shot_saving,
        );
        await showScreenshotFeedback(navigator, result);
      },
    );
  }

  /// Floating bottom-group switch button visibility (phone / desktop
  /// phone-mode). Opens the per-orientation editor dialog.
  PopupMenuItem _controlGroupItem(BuildContext context, t) {
    return PopupMenuItem(
      child: ListTile(
        mouseCursor: SystemMouseCursors.click,
        leading: const Icon(Icons.swap_horiz_rounded,
            size: kMenuTileIconSize),
        title: Text(t.control_group_floating_button),
        subtitle: Text(t.control_group_floating_desc),
      ),
      onTap: () => showControlForHover(showControlGroupFloatingDialog(context)),
    );
  }
}

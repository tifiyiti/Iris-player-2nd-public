import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/background_playback/background_playback_gate.dart';
import 'package:iris/features/background_playback/model/enum/control_target.dart';
import 'package:iris/features/background_playback/store/use_background_playback_store.dart';
import 'package:iris/features/background_playback/view/background_queue_panel.dart';
import 'package:iris/features/media_library/play_queue/ui/paged_play_queue_sheet.dart';
import 'package:iris/features/scenario_playback/view/coordinator/scenario_browser.dart';
import 'package:iris/features/window/playlist_dock/resolve_playlist_dock.dart';
import 'package:iris/features/windows/desktop_keyboard/view/shortcut_hints.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/pages/player/control_bar/control_bar_widgets/control_bar_constants.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_player_ui_store.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/widgets/a11y_tooltip.dart';
import 'package:iris/utils/platform.dart';
import 'package:iris/widgets/popup.dart';
import 'package:iris/widgets/popups/play_queue.dart';

class PlayQueueButton extends HookWidget {
  const PlayQueueButton({
    super.key,
    required this.showControlForHover,
    this.color,
    this.overlayColor,
  });

  final Future<void> Function(Future<void>) showControlForHover;
  final Color? color;
  final WidgetStateProperty<Color?>? overlayColor;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final popupDirection = useAppStore().select(context, (s) => s.defaultPopupDirection);
    final useLegacy = useAppStore().select(context, (s) => s.useLegacyStoragePersistence);
    final useScenarioDriven = useAppStore().select(context, (s) => s.useScenarioDrivenPlayback);
    final scheme = useEffectiveKeyboardScheme(context);
    final playlistPanelMode = useAppStore().select(context, (s) => s.playlistPanelMode);
    final useMetadataSettings = useAppStore().select(context, (s) => s.useMetadataSettings);
    final isFullScreen = usePlayerUiStore().select(context, (s) => s.isFullScreen);

    // Sidebar-first: dock intent wins even in narrow portrait windows.
    bool shouldDockToggle() {
      if (!isDesktop) return false;
      if (!useMetadataSettings) return false;
      if (playlistPanelMode != PlaylistPanelMode.dockedRight) return false;
      return true;
    }

    final bool isDockMode = playlistPanelMode == PlaylistPanelMode.dockedRight;
    final String hintForMode = isDockMode
        ? t.dock_mode_docked
        : t.dock_mode_floating;
    return a11yTooltipIconButton(
      context: context,
      tooltip: '${t.play_queue} ( ${shortcutHintLabelFor(ShortcutHintKind.playQueue, scheme)} ) — $hintForMode',
      icon: Icon(
        Icons.playlist_play_rounded,
        size: kPlayQueueIconSize,
        color: color,
      ),
      onPressed: () {
        if (shouldDockToggle()) {
          // Picture fullscreen drives the overlay's runtime pin; windowed
          // keeps the persisted visible flag (never touched from fullscreen).
          if (isFullscreenDockOverlayEnabled(
            isDesktop: isDesktop,
            useMetadataSettings: useMetadataSettings,
            mode: playlistPanelMode,
            isFullScreen: isFullScreen,
          )) {
            // Pin toggles on the pin state alone: hovering (peek) + tap
            // pins it open instead of dismissing it.
            final bool pinned =
                usePlayerUiStore().state.isFullscreenDockPinned;
            usePlayerUiStore().updateIsFullscreenDockPeeking(false);
            usePlayerUiStore().updateIsFullscreenDockPinned(!pinned);
            return;
          }
          useAppStore().togglePlaylistPanelVisible();
          return;
        }
        // 副音 control target: the play-queue button/sheet must present the
        // background queue, never the foreground one (see 交接 §4 错误 1).
        final bgEnabled =
            useBackgroundPlaybackStore().state.enabled &&
            useBackgroundPlaybackStore().state.controlTarget ==
                ControlTarget.background;
        if (BackgroundPlaybackGate.enabled && bgEnabled) {
          showControlForHover(
            showPopup(
              context: context,
              child: const BackgroundQueuePanel(),
              direction: popupDirection,
            ),
          );
          return;
        }
        if (useLegacy) {
          showControlForHover(
            showPopup(
              context: context,
              child: const PlayQueue(),
              direction: popupDirection,
            ),
          );
        } else if (useScenarioDriven) {
          showScenarioBrowser(context, direction: popupDirection);
        } else {
          showPagedPlayQueueSheet(context, direction: popupDirection);
        }
      },
      style: ButtonStyle(overlayColor: overlayColor),
    );
  }
}

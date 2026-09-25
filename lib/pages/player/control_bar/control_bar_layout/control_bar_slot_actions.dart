import 'package:flutter/material.dart';
import 'package:iris/features/background_playback/store/use_background_playback_store.dart';
import 'package:iris/features/background_playback/view/player_control_target_scope.dart';
import 'package:iris/features/meta_settings/meta_settings_module.dart';
import 'package:iris/features/osd/engine/osd_texts.dart';
import 'package:iris/features/osd/engine/show_player_osd.dart';
import 'package:iris/features/scenario_playback/playback/playback_provider_registry.dart';
import 'package:iris/models/player.dart';
import 'package:iris/models/store/video_display_mode.dart';
import 'package:iris/models/store/window_fit_mode.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/utils/platform.dart';
import 'package:iris/widgets/popup.dart';
import 'package:iris/widgets/popups/storages/db/storages_db.dart';
import 'package:iris/widgets/popups/storages/storages.dart';
import 'package:provider/provider.dart';

/// Shared actions for control-bar slots.
///
/// The bar button and the More-menu fallback entry invoke the SAME function so
/// a collapsed control behaves exactly like its on-bar twin — the overflow
/// model never forks behavior.

/// Shuffle, following the current control target (副音 has its own queue flag).
Future<void> toggleShuffleFromControlBar(BuildContext context) async {
  if (isBackgroundControlTarget(context)) {
    await useBackgroundPlaybackStore().toggleShuffle();
  } else {
    await PlaybackProviderRegistry.toggleShuffle();
  }
}

/// Repeat cycle (foreground only — matches the on-bar button).
Future<void> toggleRepeatFromControlBar() => PlaybackProviderRegistry.toggleRepeat();

/// Stop, following the control target. Stopping 副音 also latches its gate
/// closed so the foreground scenario is never advanced underneath it.
Future<void> stopFromControlBar(BuildContext context) async {
  if (isBackgroundControlTarget(context)) {
    useBackgroundPlaybackStore().stopGate();
    return;
  }
  useAppStore().updateAutoPlay(false);
  context.read<MediaPlayer>().pause();
  await PlaybackProviderRegistry.stop();
}

/// Fit / video-display-mode cycle: metadata era cycles the per-platform
/// display mode (with OSD), legacy era keeps the 4-way BoxFit toggle.
Future<void> cycleFitFromControlBar(BuildContext context) async {
  final t = getLocalizations(context);
  final app = useAppStore().state;
  final gateOn = app.useMetadataSettings && MetaSettingsModule.ready;
  if (gateOn) {
    await useAppStore().cycleVideoDisplayMode();
    final next = useAppStore().state;
    showPlayerOsd(OsdTexts.videoDisplayMode(
      isMobilePlatform
          ? mobileVideoDisplayModeLabel(next.mobileDisplayMode, t)
          : desktopVideoDisplayModeLabel(next.desktopDisplayMode, t),
      t,
    ));
  } else {
    useAppStore().toggleFit();
  }
}

/// 窗口适应模式 toggle (desktop only) with the transient OSD feedback.
Future<void> toggleWindowFitModeFromControlBar(BuildContext context) async {
  // Resolve the localizations BEFORE the await so no BuildContext crosses the
  // async gap.
  final t = getLocalizations(context);
  await useAppStore().toggleWindowFitMode();
  showPlayerOsd(OsdTexts.windowFitMode(
    t,
    fitVideo:
        useAppStore().state.windowFitMode == WindowFitMode.fitVideo,
  ));
}

/// Storage browser popup (legacy vs DB page follows the storage mode).
Future<void> openStorageFromControlBar(
  BuildContext context,
  Future<void> Function(Future<void>) showControlForHover,
) {
  final app = useAppStore().state;
  return showControlForHover(
    showPopup(
      context: context,
      child: app.useLegacyStoragePersistence
          ? const Storages()
          : const StoragesDb(),
      direction: app.defaultPopupDirection,
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:iris/features/scenario_playback/actions/scenario_playback_common.dart';
import 'package:iris/features/scenario_playback/actions/scenario_playback_error.dart';
import 'package:iris/features/scenario_playback/actions/scenario_resolved_actions.dart';
import 'package:iris/features/scenario_playback/store/use_playback_scenario_store.dart';
import 'package:iris/features/scenario_playback/view/dialogs/show_override_confirm_dialog.dart';
import 'package:iris/features/scenario_playback/view/dialogs/show_version_changed_dialog.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/widgets/dialogs/show_copyable_error_dialog.dart';

/// "Play the managed scenario" action used by the scenario browse page's Play
/// button (the scenario whose manager is currently open).
///
/// The target workspace is the CURRENT playback context — an active independent
/// entry's own workspace, else SystemPlaying — mirroring manual scope plays.
/// When the browsed scenario IS that workspace (SystemPlaying, or an entry's own
/// workspace scenario) there is nothing to override: just leave the manager and
/// turn a paused/stopped player into playing. Otherwise the workspace is
/// replaced from the scenario (version-changed + suppressible Override confirm)
/// and playback starts.
class ScenarioManagedPlayActions {
  const ScenarioManagedPlayActions._();

  static Future<void> playManagedScenario(
    BuildContext context, {
    required String scenarioId,
    VoidCallback? onExitAfterPlay,
  }) async {
    // Capture before any await so the dialogs/exit stay reliable after the
    // triggering page is disposed (mirrors the other play actions).
    final navigator = Navigator.of(context);
    final store = usePlaybackScenarioStore();

    try {
      final current = currentPlaybackWorkspace(store);
      if (current != null && current.id == scenarioId) {
        _leaveManager(navigator, onExitAfterPlay);
        if (!useAppStore().state.autoPlay) {
          await ScenarioResolvedActions.playCurrentWorkspace(
            scenarioId: current.id,
          );
        }
        return;
      }

      final scenario = await store.getScenario(scenarioId);
      if (scenario == null) return;

      // P5: warn when the scenario changed since it was last imported (E4).
      if (current != null) {
        final wsState = await store.getState(current.id);
        final importVersion = wsState?.importVersion;
        if (importVersion != null && importVersion < (scenario.version ?? 0)) {
          if (!navigator.mounted) return;
          final proceed = await showVersionChangedDialog(
            navigator.context,
            scenarioName: scenario.name,
          );
          if (!proceed) return;
        }
      }

      if (!navigator.mounted) return;
      final ok = await showSuppressibleOverrideConfirmDialog(
        navigator.context,
        sourceScenarioName: scenario.name,
      );
      if (!ok || !navigator.mounted) return;

      final ws = await ensurePlaybackWorkspace();
      await store.overrideWorkspace(workspace: ws, source: scenario);
      await store.bumpPlaybackVersion();
      await store.setActiveScenario(ws.id);

      _leaveManager(navigator, onExitAfterPlay);
      await ScenarioResolvedActions.playCurrentWorkspace(scenarioId: ws.id);
    } catch (e) {
      if (!navigator.mounted) return;
      final t = getLocalizations(navigator.context);
      final message = e is PlaybackUnavailableException
          ? e.displayMessage(t)
          : t.dlg_play_failed_prefix('$e');
      await showCopyableErrorDialog(
        navigator.context,
        title: t.dlg_copy_error_title,
        message: message,
      );
    }
  }

  /// Leaves the scenario manager so the video is directly visible: the caller's
  /// exit callback when provided (embedded storagedb / dock), else pop the
  /// popup route.
  static void _leaveManager(NavigatorState navigator, VoidCallback? onExit) {
    if (onExit != null) {
      onExit();
    } else if (navigator.mounted) {
      navigator.pop();
    }
  }
}

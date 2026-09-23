import 'package:iris/features/scenario_playback/actions/scenario_playback_common.dart';
import 'package:iris/features/scenario_playback/actions/scenario_resolved_actions.dart';
import 'package:iris/features/scenario_playback/store/use_playback_scenario_store.dart';
import 'package:iris/models/file.dart';
import 'package:iris/utils/path_conv.dart';

/// Switches the active playback context to [scenarioId]. Injectable so the
/// context bookkeeping can be tested without the real player/provider.
typedef ApbContextSwitcher = Future<void> Function(String scenarioId);

/// Handle of an active APB edit context: the transient workspace that holds the
/// single foreground under edit, plus the context to restore on exit.
class ApbEditSession {
  const ApbEditSession({
    required this.workspaceId,
    required this.previousScenarioId,
  });

  final String workspaceId;

  /// The scenario that was active before entering (null when none).
  final String? previousScenarioId;
}

/// The 副音 mapping manager's dedicated edit context ("fg-bg-apb scenario").
///
/// Entering installs the edited foreground as the ONLY explicit item of a
/// fresh transient [ScenarioKind.entryWorkspace] and switches playback to it,
/// so the APB editor can drive a real single-fg pair without touching the
/// SystemPlaying (or any other entry) workspace. Exiting restores the previous
/// context and deletes the transient workspace.
abstract final class ApbEditContext {
  /// Creates the transient single-fg workspace and switches to it. Returns the
  /// session, or null when [fg] has no usable identity.
  static Future<ApbEditSession?> enter({
    required FileItem fg,
    PlaybackScenarioStore? store,
    ApbContextSwitcher? switchContext,
  }) async {
    final storageId = fg.storageId;
    final path = fg.path.join('/');
    if (storageId.isEmpty || path.isEmpty) return null;

    final scenarioStore = store ?? usePlaybackScenarioStore();
    await scenarioStore.ensureReady();
    final previous = scenarioStore.state.activeScenarioId;

    final ws = await scenarioStore.ensureEntryWorkspace(null);
    await scenarioStore.clearSources(ws.id);
    await scenarioStore.clearExplicitItems(ws.id);
    await scenarioStore.clearTemporaryExcludes(ws.id);
    await scenarioStore.addExplicitItemFor(
      scenarioId: ws.id,
      storageId: storageId,
      path: canonicalOccurrencePath(path),
    );
    await resetManualScopeOrigin(ws.id);
    scenarioStore.bumpWorkspaceOverrideRevision();
    await scenarioStore.bumpPlaybackVersion();

    await _switch(switchContext, ws.id);
    return ApbEditSession(
      workspaceId: ws.id,
      previousScenarioId: previous,
    );
  }

  /// Restores the context active before [session], then removes the transient
  /// workspace. Falls back to SystemPlaying when the previous context is gone.
  static Future<void> exit(
    ApbEditSession session, {
    PlaybackScenarioStore? store,
    ApbContextSwitcher? switchContext,
  }) async {
    final scenarioStore = store ?? usePlaybackScenarioStore();
    await scenarioStore.ensureReady();

    var target = session.previousScenarioId;
    if (target == null || await scenarioStore.getScenario(target) == null) {
      target = (await scenarioStore.ensureSystemPlayingScenario()).id;
    }
    await _switch(switchContext, target);

    // Only after the context has moved away: drop the transient workspace.
    if (target != session.workspaceId) {
      await scenarioStore.deleteEntryWorkspace(session.workspaceId);
    }
  }

  static Future<void> _switch(
    ApbContextSwitcher? switcher,
    String scenarioId,
  ) {
    final fn = switcher ??
        (id) => ScenarioResolvedActions.switchPlaybackContext(id,
            autoplay: false);
    return fn(scenarioId);
  }
}

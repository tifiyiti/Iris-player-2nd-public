/// Shared internals of the scenario-driven play actions (override / append /
/// resolved). Kept here so the focused action modules stay thin and no caller
/// needs to reach into the other modules' privates.
library;

import 'package:iris/features/app_identity/store/use_app_identity_store.dart';
import 'package:iris/features/scenario_playback/model/domain/scenario.dart';
import 'package:iris/features/scenario_playback/playback/playback_provider.dart';
import 'package:iris/features/scenario_playback/playback/playback_provider_registry.dart';
import 'package:iris/features/scenario_playback/store/use_playback_scenario_store.dart';
import 'package:iris/models/file.dart';
import 'package:iris/utils/path_conv.dart';

/// A source specification to install into the SystemPlayingScenario.
typedef ScenarioSourceSpec = ({String storageId, String path, bool recursive});

/// Ensures the SystemPlaying workspace row exists and activates it.
Future<Scenario> ensureSystemPlayingScenario() async {
  final store = usePlaybackScenarioStore();
  final sys = await store.ensureSystemPlayingScenario();
  if (store.state.activeScenarioId != sys.id) {
    await store.setActiveScenario(sys.id);
  }
  return sys;
}

/// The workspace the CURRENT playback context uses: an active INDEPENDENT
/// entry's own workspace when one is active, otherwise SystemPlaying. Shared
/// entries resolve to SystemPlaying like the default icon.
///
/// Null only before any workspace row exists (e.g. fresh install with no data).
Scenario? currentPlaybackWorkspace(PlaybackScenarioStore store) {
  final identity = useAppIdentityStore();
  final entryId = identity.state.activeEntryId;
  final entry = entryId == null ? null : identity.entryById(entryId);
  if (entry != null && !entry.sharedWithDefault) {
    final id = entry.workspaceScenarioId;
    if (id != null) {
      for (final s in store.state.scenarios) {
        if (s.id == id) return s;
      }
    }
  }
  return store.systemPlayingScenario;
}

/// Resolves and activates the workspace that a MANUAL scope play
/// (folder/lib/selection) and the resolved-item override should target.
///
/// - An active INDEPENDENT entry → its OWN workspace (so the entry keeps
///   saving its own state as the user plays).
/// - Otherwise → SystemPlaying.
Future<Scenario> ensurePlaybackWorkspace() async {
  final store = usePlaybackScenarioStore();
  final identity = useAppIdentityStore();
  final entryId = identity.state.activeEntryId;
  final entry = entryId == null ? null : identity.entryById(entryId);

  final Scenario ws;
  if (entry != null && !entry.sharedWithDefault) {
    ws = await store.ensureEntryWorkspace(entry.workspaceScenarioId);
  } else {
    ws = await store.ensureSystemPlayingScenario();
  }
  if (store.state.activeScenarioId != ws.id) {
    await store.setActiveScenario(ws.id);
  }
  return ws;
}

/// Starts playback of [tapped] inside the (already configured) [scenario]
/// workspace via the scenario playback provider.
Future<void> playInScenario(
  Scenario scenario,
  FileItem tapped,
  String storageId,
  String itemPath,
) {
  final canonical = canonicalOccurrencePath(itemPath);
  final entry = PlaybackEntry(
    file: tapped,
    storageId: storageId,
    path: canonical,
    key: '$storageId:$canonical',
  );
  return PlaybackProviderRegistry.scenario.play(entry);
}

/// Clears the workspace's origin marker after a MANUAL scope play
/// (folder/lib/selection): the workspace no longer mirrors any saved
/// scenario, so Sync-back must be disabled and `playResolvedItem` must not
/// treat the stale origin as a direct mirror (E1/F2).
Future<void> resetManualScopeOrigin(String scenarioId) async {
  final store = usePlaybackScenarioStore();
  final state = await store.getState(scenarioId);
  if (state == null || state.originScenarioId == null) return;
  await store.updateState(state.copyWith(
    originScenarioId: null,
    importVersion: null,
    importedAt: null,
  ));
}

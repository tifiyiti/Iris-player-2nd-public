import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/media_library/search/store/search_browser_store.dart';
import 'package:iris/features/media_library/search/view/media_search_page.dart';
import 'package:iris/features/media_library/store/use_media_lib_browser_store.dart';
import 'package:iris/features/scenario_playback/view/browse/scenario_browse_page.dart';
import 'package:iris/features/scenario_playback/view/coordinator/scenario_browser_store.dart';
import 'package:iris/features/scenario_playback/view/preview/scenario_preview_page.dart';
import 'package:iris/features/scenario_playback/view/queue/scenario_queue_page.dart';
import 'package:iris/features/scenario_playback/actions/scenario_playback_common.dart'
    show currentPlaybackWorkspace;
import 'package:iris/features/scenario_playback/view/sources/scenario_sources_page.dart';
import 'package:iris/features/scenario_playback/store/use_playback_scenario_store.dart';
import 'package:iris/store/use_storage_store.dart';
import 'package:iris/widgets/popup.dart';
import 'package:iris/widgets/popups/storages/db/storages_db.dart';

/// Coordinator of the scenario browser (single-scenario manager).
///
/// Like [StoragesDb], it performs whole-interface replacement: it renders
/// exactly one sub-interface (Queue / Sources / Browse / Preview) based on the
/// [ScenarioBrowserStore] mode. Each sub-interface manages its own UI, data
/// source and state.
///
/// When [embeddedInStoragesDb] is true the browser is rendered as a full-page
/// sub-interface of [StoragesDb] (BrowserOpenMode.scenario): back/home close it
/// in place via [MediaLibBrowserStore.openScenarioTab]. Otherwise it is a
/// standalone popup (e.g. from the player's queue button) whose back/home
/// replace the popup with the storagedb Playback Scenario tab.
///
/// [modeQueueOverride] renders the Playing Queue as a TEMPORARY page without
/// touching the persisted [ScenarioBrowserStore] mode, so the queue button
/// never pollutes the scenario manager's state (the manager is reopened in its
/// own sources/browse mode).
class ScenarioBrowser extends HookWidget {
  final PopupDirection direction;

  /// Close (X) behavior. Defaults to popping the current popup route.
  final void Function(BuildContext context)? onExit;

  /// True when rendered inside [StoragesDb] via `openScenario()`.
  final bool embeddedInStoragesDb;

  /// When true the Playing Queue page is shown (temporary, recreated on each
  /// open) regardless of the persisted [ScenarioBrowserStore] mode.
  final bool modeQueueOverride;

  /// True when hosted inside the right-side dock panel (see
  /// `ScenarioQueuePage.dockedPanel`), so the queue must not be repainted with
  /// the standalone floating-popup theme.
  final bool dockedPanel;

  const ScenarioBrowser({
    super.key,
    required this.direction,
    this.onExit,
    this.embeddedInStoragesDb = false,
    this.modeQueueOverride = false,
    this.dockedPanel = false,
  });

  @override
  Widget build(BuildContext scenario) {
    final store = useScenarioBrowserStore();
    final ScenarioBrowserMode mode;
    if (modeQueueOverride) {
      // Queue-override context (floating popup / dock): mount seeds the local
      // override at the queue and unmount resets it, so pages switch IN PLACE
      // via the store without ever writing the persisted manager mode.
      useEffect(() {
        store.setQueueOverrideMode(ScenarioBrowserMode.queue);
        return () => store.resetQueueOverride();
      }, const []);
      mode = store.select(scenario, (s) => s.queueOverrideMode) ??
          ScenarioBrowserMode.queue;
    } else {
      mode = store.select(scenario, (s) => s.mode);
    }

    return switch (mode) {
      ScenarioBrowserMode.queue =>
        ScenarioQueuePage(
          direction: direction,
          onExit: onExit,
          embeddedInStoragesDb: embeddedInStoragesDb,
          modeQueueOverride: modeQueueOverride,
          dockedPanel: dockedPanel,
        ),
      ScenarioBrowserMode.sources =>
        ScenarioSourcesPage(
          direction: direction,
          onExit: onExit,
          embeddedInStoragesDb: embeddedInStoragesDb,
          queueOverride: modeQueueOverride,
        ),
      ScenarioBrowserMode.browse =>
        ScenarioBrowsePage(
          direction: direction,
          onExit: onExit,
          embeddedInStoragesDb: embeddedInStoragesDb,
          queueOverride: modeQueueOverride,
        ),
      ScenarioBrowserMode.preview =>
        ScenarioPreviewPage(
          direction: direction,
          onExit: onExit,
          embeddedInStoragesDb: embeddedInStoragesDb,
          queueOverride: modeQueueOverride,
        ),
      ScenarioBrowserMode.search =>
        MediaSearchPage(
          direction: direction,
          onExit: onExit,
          embeddedInStoragesDb: embeddedInStoragesDb,
          queueOverride: modeQueueOverride,
        ),
    };
  }
}

/// Opens the scenario browser as a popup on top of the current route (e.g.
/// from the player's play queue button).
///
/// The Playing Queue button ALWAYS opens the SystemPlayingScenario resolved
/// queue — never a Saved Scenario (C2/P4). It is a temporary page
/// ([ScenarioBrowser.modeQueueOverride]) that never writes the persisted
/// [ScenarioBrowserStore] mode.
void showScenarioBrowser(
  BuildContext scenario, {
  required PopupDirection direction,
}) {
  _alignQueueWorkspaceToMode();
  showPopup(
    context: scenario,
    direction: direction,
    child: ScenarioBrowser(direction: direction, modeQueueOverride: true),
  );
}

/// Aligns the active scenario with the CURRENT playback context before the
/// queue popup opens, so the Playing Queue never shows the wrong queue: an
/// active independent entry's own workspace, else SystemPlaying. This also
/// corrects the "managing a saved scenario" case where the active scenario was
/// switched away from what is actually playing.
void _alignQueueWorkspaceToMode() {
  final store = usePlaybackScenarioStore();
  final target = currentPlaybackWorkspace(store);
  if (target != null && store.state.activeScenarioId != target.id) {
    store.setActiveScenario(target.id);
  }
}

/// Replaces the current popup (e.g. [StoragesDb]) with the SystemPlaying
/// queue popup — used by the scenario tab tiles after Play Override/Append so
/// the popup stack stays flat.
void replaceScenarioBrowser(
  BuildContext scenario, {
  required PopupDirection direction,
}) {
  _alignQueueWorkspaceToMode();
  replacePopup(
    context: scenario,
    child: ScenarioBrowser(direction: direction, modeQueueOverride: true),
    direction: direction,
  );
}

/// Opens the scenario manager as a full-page sub-interface of [StoragesDb]
/// (BrowserOpenMode.scenario) — the "open-in-folder"-style entry used by the
/// scenario tiles. Back/home inside the sub-interface return to the tabs.
Future<void> openScenarioManager(
  BuildContext context, {
  required String scenarioId,
}) async {
  final store = usePlaybackScenarioStore();
  await store.setActiveScenario(scenarioId);
  if (!context.mounted) return;
  useStorageStore()
    ..updateCurrentStorage(null)
    ..updateCurrentPath([]);
  useScenarioBrowserStore().setMode(ScenarioBrowserMode.sources);
  useMediaLibBrowserStore().openScenario();
}

/// Degrades a stale search session back to the SystemPlaying scenario manager
/// (sources mode) — v6-D5: after the SystemPlaying workspace was overridden, a
/// parked search session's cached results no longer reflect the playing queue,
/// so reopening the storagedb lands here showing the CURRENT explicit items
/// instead of resuming the old search page. Clears the search seeds and resets
/// the pin via [SearchBrowserStore.destroySession].
Future<void> openSystemPlayingScenarioPage() async {
  final store = usePlaybackScenarioStore();
  final sys = store.systemPlayingScenario;
  if (sys != null) {
    await store.setActiveScenario(sys.id);
  }
  useSearchBrowserStore()
    ..destroySession()
    ..clearAll();
  useScenarioBrowserStore().setMode(ScenarioBrowserMode.sources);
  useMediaLibBrowserStore().openScenario();
}

/// Opens the temporary Preview (resolved queue) of [scenarioId] as a full-page
/// sub-interface of [StoragesDb], regenerated fresh from scenario data every
/// time. Read-only: the active scenario is NOT changed and no state persists.
///
/// [returnMode] records the interface active before the preview so back/exit
/// can restore it (e.g. `sources`); when null back falls back to the storagedb
/// tabs.
void openScenarioPreview(
  BuildContext context, {
  required String scenarioId,
  ScenarioBrowserMode? returnMode,
  bool queueOverride = false,
}) {
  final b = useScenarioBrowserStore();
  b
    ..setPreviewScenarioId(scenarioId)
    ..setPreviewReturnMode(returnMode);
  if (queueOverride) {
    b.setQueueOverrideMode(ScenarioBrowserMode.preview);
  } else {
    b.setMode(ScenarioBrowserMode.preview);
    useMediaLibBrowserStore().openScenario();
  }
}

/// Where "Manage scenario" from the playing queue lands.
///
/// Queue-owned manage page — completely independent from [StoragesDb] routing.
/// Both floating popup and docked panel use the in-place queueOverride mode,
/// so back/home never touch [MediaLibBrowserStore] and cannot pollute storagedb.
/// Data source stays one truth via [PlaybackScenarioStore] / [DbModule.scenarioRepo].
enum ManageFromQueueTarget { replaceCurrentRoute, inPlaceOverridePanel }

@Deprecated('Queue now always uses in-place override; kept for compat')
ManageFromQueueTarget resolveManageFromQueueTarget({required bool canPop}) =>
    ManageFromQueueTarget.inPlaceOverridePanel;

/// "Manage scenario" from the Playing Queue: shows the scenario's Sources
/// (root) inside the same queue popup/panel (no StoragesDb involved).
/// Back returns to queue, Home stays at Sources root, X closes popup.
Future<void> openManagerFromQueue(
  BuildContext context, {
  required String scenarioId,
  required PopupDirection direction,
}) async {
  final store = usePlaybackScenarioStore();
  await store.setActiveScenario(scenarioId);
  if (!context.mounted) return;
  // Independent from MediaLibBrowserStore / StoragesDb.
  // Clear any browse seed so Sources starts at root.
  useScenarioBrowserStore()
    ..setBrowseSeed(storageId: null, path: null)
    ..setQueueOverrideMode(ScenarioBrowserMode.sources);
}

/// Jumps to the storagedb Playback Scenario tab.
///
/// Used by the standalone (non-embedded) scenario popup: replaces the current
/// popup route with [StoragesDb] and lands on the Playback Scenario tab.
/// Resets the browser open mode first so the fresh [StoragesDb] renders the
/// tabs rather than any stale scenario/lib sub-interface.
Future<void> openPlaybackScenariosTab(
  BuildContext context,
  PopupDirection direction,
) async {
  useMediaLibBrowserStore().openScenarioTab();
  await replacePopup(
    context: context,
    child: const StoragesDb(),
    direction: direction,
  );
}

/// Returns to the storagedb Playback Scenario tab from within the scenario
/// browser. When embedded, [MediaLibBrowserStore.openScenarioTab] re-renders
/// the surrounding [StoragesDb] in place; otherwise the popup is replaced.
///
/// [queueOverride] is the CALLING browser instance's own flag (never the global
/// [ScenarioBrowserStore.queueOverrideActive]): a concurrently-mounted docked
/// queue panel sets the global override slot, so an embedded storagedb manager
/// must not mistake that for its own override context.
///
/// Queue-override panels (floating queue popup / docked queue panel) have no
/// storagedb tab to land on — Home returns to the queue inside the panel
/// instead (a popup replacement in the docked case would pop the ROOT route).
void goToScenarioTab(
  BuildContext context,
  PopupDirection direction, {
  required bool embedded,
  required bool queueOverride,
}) {
  final store = useScenarioBrowserStore();
  if (queueOverride) {
    store.setQueueOverrideMode(ScenarioBrowserMode.queue);
    return;
  }
  if (embedded) {
    useMediaLibBrowserStore().openScenarioTab();
  } else {
    openPlaybackScenariosTab(context, direction);
  }
}

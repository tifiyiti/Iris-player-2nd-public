import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'scenario_browser_store.freezed.dart';

/// Display modes of the scenario browser.
///
/// The coordinator renders one sub-interface at a time (whole-interface
/// replacement, like storage list <-> files paged browser).
///
/// [ScenarioBrowserMode.queue] is transient and entered via
/// [ScenarioBrowser.modeQueueOverride] — it is never stored here. The
/// persisted modes are [sources]/[browse] (scenario manage) and [preview]
/// (transient preview page; also not persisted beyond the current session).
enum ScenarioBrowserMode { queue, sources, browse, preview, search }

@freezed
abstract class ScenarioBrowserState with _$ScenarioBrowserState {
  const factory ScenarioBrowserState({
    @Default(ScenarioBrowserMode.queue) ScenarioBrowserMode mode,

    /// Temporary page currently rendered inside a [ScenarioBrowser] mounted
    /// with `modeQueueOverride: true` (floating queue popup / docked queue
    /// panel). Null = no queue-override browser is mounted. Deliberately NOT
    /// the persisted [mode]: the queue button must never pollute the scenario
    /// manager's state, yet Search/Manage inside the queue must still be able
    /// to switch the visible page IN PLACE (a route replacement in the docked
    /// case would pop the ROOT route — white screen, player unmounted).
    ScenarioBrowserMode? queueOverrideMode,
  }) = _ScenarioBrowserState;
}

/// Ephemeral UI state controlling which sub-interface the scenario browser
/// shows. Per-sub-interface state lives in each sub-interface's own
/// data source / page.
class ScenarioBrowserStore extends Store<ScenarioBrowserState> {
  ScenarioBrowserStore() : super(const ScenarioBrowserState());

  /// Seed for the next Browse (Layer-2) entry: the storage/path a Layer-1
  /// source/exclude navigated from. Read once by the browse page.
  String? browseStorageId;
  String? browsePath;

  /// Scenario whose resolved queue the temporary preview page renders. Read
  /// once by the preview page; never persisted (preview is regenerated fresh
  /// from scenario data each time it is opened).
  String? previewScenarioId;

  /// Mode active before the preview was opened. The preview's back/exit
  /// restores it (e.g. `sources`); null falls back to the storagedb tabs.
  ScenarioBrowserMode? previewReturnMode;

  void setMode(ScenarioBrowserMode mode) {
    set(state.copyWith(mode: mode));
  }

  /// Current queue-override page (null when no override browser is mounted).
  ScenarioBrowserMode? get queueOverrideMode => state.queueOverrideMode;

  /// True while a `modeQueueOverride` browser (floating queue popup / docked
  /// queue panel) is mounted — queue Search/Manage actions must switch pages
  /// via [setQueueOverrideMode] instead of writing the persisted [mode].
  bool get queueOverrideActive => state.queueOverrideMode != null;

  void setQueueOverrideMode(ScenarioBrowserMode mode) {
    set(state.copyWith(queueOverrideMode: mode));
  }

  void resetQueueOverride() {
    set(state.copyWith(queueOverrideMode: null));
  }

  /// Sets the scenario whose resolved queue the temporary preview page renders.
  void setPreviewScenarioId(String scenarioId) {
    previewScenarioId = scenarioId;
  }

  /// Records the mode active before the preview so back can restore it.
  void setPreviewReturnMode(ScenarioBrowserMode? mode) {
    previewReturnMode = mode;
  }

  /// Seeds the Layer-2 browse to start at [storageId]/[path] instead of the
  /// storage list.
  void setBrowseSeed({String? storageId, String? path}) {
    browseStorageId = storageId;
    browsePath = path;
  }

  /// One-shot flag: manager was entered from the playing queue. The next back
  /// on the Layer-1 sources page returns to the queue; after consuming, later
  /// backs fall through to tabs. Mirrors the one-shot restore seeds.
  bool managerEnteredFromQueue = false;

  void setManagerEnteredFromQueue(bool v) => managerEnteredFromQueue = v;

  bool consumeManagerEnteredFromQueue() {
    final v = managerEnteredFromQueue;
    managerEnteredFromQueue = false;
    return v;
  }
}

ScenarioBrowserStore useScenarioBrowserStore() =>
    create(() => ScenarioBrowserStore());

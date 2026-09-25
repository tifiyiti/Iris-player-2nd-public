import 'package:flutter/material.dart';
import 'package:iris/features/scenario_playback/scan/service/scenario_source_refresh_service.dart';
import 'package:iris/store/use_storage_store.dart';

/// UI-facing entry for the "扫描更新源数据" action.
///
/// Thin facade so every surface (player more-menu, scenario tile more-menu,
/// queue toolbar, sources toolbar) shares the exact same launch path and
/// offline-gating rule.
abstract final class ScenarioSourceScanCommand {
  /// In-flight refresh for the whole app, or null when idle.
  ///
  /// Single-flight: the scan store only rejects a SECOND scan once one has
  /// actually started, but [ScenarioSourceRefreshService] does a lot of async
  /// work (DB reads, remote preflight) before it ever calls `startScan`. A
  /// second trigger inside that window (a double-tap, or the same action from
  /// two surfaces) would start a duplicate batch and stack its own options +
  /// summary dialogs. Joining the active run collapses them into one.
  static Future<bool>? _inFlight;

  /// Test seam: replaces the refresh runner so single-flight can be exercised
  /// without a live database, scenario, or filesystem. Production leaves it
  /// null and [run] builds a real [ScenarioSourceRefreshService].
  @visibleForTesting
  static Future<bool> Function(BuildContext context, String scenarioId)?
      debugRunOverride;

  /// Whether the action should be enabled right now.
  ///
  /// A scenario's source storages are only known after an async DB read, so UI
  /// gating uses the conservative whole-app signal: when every configured
  /// storage is known-disconnected the action is pointless and is greyed out.
  /// An unknown/optimistic status stays enabled — the service re-checks each
  /// remote storage with a real preflight before scanning anyway.
  static bool isEnabled() {
    final statuses = useStorageStore().state.storageConnectionStatus;
    if (statuses.isEmpty) return true;
    return statuses.values.any((connected) => connected);
  }

  /// Launches the refresh for [scenarioId]. Returns true when a refresh ran.
  ///
  /// A concurrent call returns the in-flight run's result instead of starting
  /// a second one (see [_inFlight]).
  static Future<bool> run(
    BuildContext context, {
    required String scenarioId,
  }) {
    final active = _inFlight;
    if (active != null) return active;
    final runner = debugRunOverride ??
        (BuildContext ctx, String id) => ScenarioSourceRefreshService()
            .refreshScenarioSources(context: ctx, scenarioId: id);
    final future =
        runner(context, scenarioId).whenComplete(() => _inFlight = null);
    _inFlight = future;
    return future;
  }
}

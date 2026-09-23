import 'package:flutter/material.dart';
import 'package:iris/features/scenario_playback/scan/service/scenario_source_refresh_service.dart';
import 'package:iris/store/use_storage_store.dart';

/// UI-facing entry for the "扫描更新源数据" action.
///
/// Thin facade so every surface (player more-menu, scenario tile more-menu,
/// queue toolbar, sources toolbar) shares the exact same launch path and
/// offline-gating rule.
abstract final class ScenarioSourceScanCommand {
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
  static Future<bool> run(
    BuildContext context, {
    required String scenarioId,
  }) {
    return ScenarioSourceRefreshService().refreshScenarioSources(
      context: context,
      scenarioId: scenarioId,
    );
  }
}

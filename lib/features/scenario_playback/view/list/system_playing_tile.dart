import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/scenario_playback/model/domain/scenario.dart';
import 'package:iris/features/scenario_playback/actions/scenario_playback_actions.dart';
import 'package:iris/features/scenario_playback/store/use_playback_scenario_store.dart';
import 'package:iris/features/scenario_playback/view/coordinator/scenario_browser.dart';
import 'package:iris/store/use_app_store.dart';

/// Pinned tile of the SystemPlayingScenario (C2/A1).
///
/// Always first in the Scenario tab (sequence number 1). Cannot be deleted or
/// multi-selected. Tap opens the scenario manager (Layer-1); the trailing Play
/// button closes the popup (direct video) and — when the player is paused or
/// stopped — starts playback of the current workspace. Saving is available
/// ONLY from the playing queue's Save button (D14).
class SystemPlayingTile extends HookWidget {
  const SystemPlayingTile({super.key, required this.scenario});

  final Scenario scenario;

  @override
  Widget build(BuildContext context) {
    final store = usePlaybackScenarioStore();
    final activeId = store.select(context, (s) => s.activeScenarioId);
    final originId = useFuture(useMemoized(
      () async => (await store.getState(scenario.id))?.originScenarioId,
      [],
    )).data;
    final isActive = scenario.id == activeId;

    Future<void> playNow() async {
      if (!context.mounted) return;
      // Close the popup entirely so the video is visible directly; start
      // playback of the current workspace when the player is paused or stopped
      // (autoPlay == false), and keep playing when already playing.
      Navigator.of(context).pop();
      if (!useAppStore().state.autoPlay) {
        await ScenarioPlaybackActions.playCurrentWorkspace();
      }
    }

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      color: Theme.of(context).colorScheme.primaryContainer.withAlpha(60),
      child: ListTile(
        leading: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 16),
          child: Text(
            '1',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              color: isActive ? Theme.of(context).colorScheme.primary : null,
            ),
          ),
        ),
        title: const Text('Playing', style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
          originId != null ? 'Synced from origin' : 'Current playing workspace',
        ),
        trailing: IconButton(
          icon: const Icon(Icons.play_arrow_rounded),
          tooltip: 'Play',
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          onPressed: () => playNow(),
        ),
        onTap: () => openScenarioManager(context, scenarioId: scenario.id),
      ),
    );
  }
}

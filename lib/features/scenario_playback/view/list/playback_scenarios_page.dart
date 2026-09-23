import 'package:flutter/material.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/media_library/selection/selection_action.dart';
import 'package:iris/features/media_library/selection/selection_overlay_bar.dart';
import 'package:iris/features/scenario_playback/store/use_playback_scenario_store.dart';
import 'package:iris/features/scenario_playback/view/list/playback_scenarios_list_page.dart';
import 'package:iris/features/scenario_playback/view/list/use_playback_scenarios_selection.dart';

/// Playback Scenario tab content: a plain list plus a floating selection bar.
///
/// Mirrors [MediaLibPage].
class PlaybackScenariosPage extends HookWidget {
  const PlaybackScenariosPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = usePlaybackScenarioStore();
    final ids = store.select(context, (s) => s.scenarios.map((e) => e.id).toList());
    final selectionStore = usePlaybackScenariosSelectionStore();
    final selection = selectionStore.controller;

    Future<void> handleDelete() async {
      final selectedIds = selection.selected.toList();
      if (selectedIds.isEmpty) return;

      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          final t = getLocalizations(ctx);
          return AlertDialog(
            title: Text(t.scn_delete_many_title),
            content: Text(t.scn_delete_many_body(selectedIds.length)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(t.scn_cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(t.scn_delete),
              ),
            ],
          );
        },
      );
      if (ok != true) return;

      for (final id in selectedIds) {
        await store.deleteScenario(id);
      }
      selection.exit();
    }

    return Stack(
      children: [
        const PlaybackScenariosListPage(),
        SelectionOverlayBar<String>(
          controller: selection,
          allItems: ids,
          actions: [
            SelectionAction<String>(
              icon: const Icon(Icons.delete_outline),
              onPressed: (_, __) async {
                await handleDelete();
              },
            ),
          ],
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:iris/features/scenario_playback/view/dialogs/show_create_scenario_dialog.dart';
import 'package:iris/features/scenario_playback/view/list/playback_scenario_sort_menu.dart';
import 'package:iris/features/scenario_playback/view/list/playback_scenarios_page.dart';
import 'package:iris/features/scenario_playback/view/list/use_playback_scenarios_selection.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/widgets/interface/tab_page_module.dart';

class PlaybackScenarioTabPage implements TabPageModule {
  @override
  String title(BuildContext context) =>
      getLocalizations(context).storages_scenarios;

  @override
  Widget buildPage(BuildContext context) {
    return const PlaybackScenariosPage();
  }

  @override
  Widget? buildAction(BuildContext context) {
    final selection = usePlaybackScenariosSelectionStore().controller;

    return ListenableBuilder(
      listenable: selection,
      builder: (_, __) {
        if (selection.isSelecting) return const SizedBox.shrink();

        return const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PlaybackScenarioSortMenu(),
            SizedBox(width: 8),
            _CreateScenarioButton(),
          ],
        );
      },
    );
  }
}

class _CreateScenarioButton extends StatelessWidget {
  const _CreateScenarioButton();

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: getLocalizations(context).storages_create_scenario,
      icon: const Icon(Icons.add_rounded),
      onPressed: () => showCreateScenarioDialog(context),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/media_library/search/store/search_browser_store.dart';
import 'package:iris/features/paginated_browser/paginated_browser_page.dart';
import 'package:iris/features/scenario_playback/store/use_playback_scenario_store.dart';
import 'package:iris/features/scenario_playback/view/browse/paged_scenario_browse_data_source.dart';
import 'package:iris/features/scenario_playback/view/coordinator/scenario_browser.dart';
import 'package:iris/features/scenario_playback/view/coordinator/scenario_browser_store.dart';
import 'package:iris/widgets/popup.dart';

/// Browse (Directory Explorer, Layer-2) sub-interface of the scenario browser.
///
/// Drills into storages/folders in the media database and lets the user add
/// sources, explicit includes and exclusion rules. When entered from a Layer-1
/// source/exclude it starts at that storage/path. Back navigates up the tree;
/// at the storage list it returns to the Sources mode. Home goes to the
/// Playback Scenario tab.
class ScenarioBrowsePage extends HookWidget {
  final PopupDirection direction;
  final void Function(BuildContext context)? onExit;
  final bool embeddedInStoragesDb;

  /// True when this page belongs to a `modeQueueOverride` browser (floating
  /// queue popup / docked panel). Never read the global
  /// [ScenarioBrowserStore.queueOverrideActive] here: a concurrently-mounted
  /// dock would otherwise hijack the embedded storagedb manager's routing.
  final bool queueOverride;

  const ScenarioBrowsePage({
    super.key,
    required this.direction,
    this.onExit,
    this.embeddedInStoragesDb = false,
    this.queueOverride = false,
  });

  @override
  Widget build(BuildContext context) {
    final store = usePlaybackScenarioStore();
    final scenarioId = store.select(context, (s) => s.activeScenarioId);

    final browseStore = useScenarioBrowserStore();
    final seedStorageId = browseStore.browseStorageId;
    final seedPath = browseStore.browsePath;

    // Consume the search-page return position ONCE (v5-D1/v6-D2) — kept in a
    // ref so the restored position stays stable for the data source lifetime.
    final searchBrowserStore = useSearchBrowserStore();
    final restoreRef = useRef<BrowseReturnPosition?>(null);
    if (restoreRef.value == null) {
      restoreRef.value = searchBrowserStore.consumeBrowseRestore();
    }

    final dataSource = useMemoized(
      () => PagedScenarioBrowseDataSource(
        scenarioId: scenarioId ?? '',
        initialStorageId: seedStorageId,
        initialPath: seedPath,
        restorePosition: restoreRef.value,
        queueOverride: queueOverride,
        onExitAfterPlay: () => _close(context),
      ),
      [scenarioId, seedStorageId, seedPath, restoreRef.value, queueOverride],
    );
    useEffect(() => () => dataSource.dispose(), [dataSource]);

    if (scenarioId == null) {
      return const SizedBox.shrink();
    }

    return PaginatedBrowserPage(
      dataSource: dataSource,
      onHomePage: () {
        if (queueOverride) {
          useScenarioBrowserStore()
            ..setBrowseSeed(storageId: null, path: null)
            ..setQueueOverrideMode(ScenarioBrowserMode.sources);
          return;
        }
        goToScenarioTab(context, direction,
            embedded: embeddedInStoragesDb, queueOverride: queueOverride);
      },
      onClose: () => _close(context),
      showHomePage: true,
      showBackButton: true,
    );
  }

  void _close(BuildContext context) {
    final exit = onExit;
    if (exit != null) {
      exit(context);
    } else {
      Navigator.of(context).pop();
    }
  }
}

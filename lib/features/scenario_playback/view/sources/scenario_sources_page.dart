import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/media_library/search/store/search_browser_store.dart';
import 'package:iris/features/paginated_browser/paginated_browser_page.dart';
import 'package:iris/features/scenario_playback/store/use_playback_scenario_store.dart';
import 'package:iris/features/scenario_playback/view/coordinator/scenario_browser.dart';
import 'package:iris/features/scenario_playback/view/coordinator/scenario_browser_store.dart';
import 'package:iris/features/scenario_playback/view/sources/paged_scenario_sources_data_source.dart';
import 'package:iris/widgets/popup.dart';

/// Sources (Manage) sub-interface of the scenario browser.
///
/// Shows the active scenario's sources, exclude rules and explicit includes
/// as one paginated management list (Layer-1). "Preview resolve queue" opens
/// the independent temporary Preview page (see [openScenarioPreview]).
///
/// Back behavior (user spec):
/// - Layer-1 (sources/excludes): back returns to the storagedb tabs when
///   embedded; in the standalone popup it returns to the play queue.
/// - Home always returns to the storagedb tabs.
class ScenarioSourcesPage extends HookWidget {
  final PopupDirection direction;
  final void Function(BuildContext context)? onExit;
  final bool embeddedInStoragesDb;

  /// True when this page belongs to a `modeQueueOverride` browser (floating
  /// queue popup / docked panel). Never read the global
  /// [ScenarioBrowserStore.queueOverrideActive] here: a concurrently-mounted
  /// dock would otherwise hijack the embedded storagedb manager's routing.
  final bool queueOverride;

  const ScenarioSourcesPage({
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

    // Consume the search-page return position ONCE (v5-D1/v6-D3): the restored
    // value must stay stable for the data source lifetime, so it is captured in
    // a ref rather than re-consumed on every rebuild.
    final searchBrowserStore = useSearchBrowserStore();
    final restoreRef = useRef<PagedScenarioSourcesRestore?>(null);
    if (restoreRef.value == null) {
      restoreRef.value = searchBrowserStore.consumeSourcesRestore();
    }

    final dataSource = useMemoized(
      () => PagedScenarioSourcesDataSource(
        scenarioId: scenarioId ?? '',
        embeddedInStoragesDb: embeddedInStoragesDb,
        queueOverride: queueOverride,
        restorePosition: restoreRef.value,
      ),
      [scenarioId, embeddedInStoragesDb, queueOverride, restoreRef.value],
    );

    useEffect(() => () => dataSource.dispose(), [dataSource]);

    if (scenarioId == null) {
      return const SizedBox.shrink();
    }

    return PaginatedBrowserPage(
      dataSource: dataSource,
      onHomePage: () {
        // Queue-owned Manage: Home is Sources root (clear browse seed), X is close.
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

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:iris/features/media_library/search/data_source/media_search_data_source.dart';
import 'package:iris/features/media_library/search/model/search_result_item.dart';
import 'package:iris/features/media_library/search/store/search_browser_store.dart';
import 'package:iris/features/media_library/search/store/use_media_lib_search_store.dart';
import 'package:iris/features/media_library/search/view/widgets/media_search_bar.dart';
import 'package:iris/features/media_library/store/use_media_lib_browser_store.dart';
import 'package:iris/features/paginated_browser/paginated_browser_controller.dart';
import 'package:iris/features/paginated_browser/paginated_browser_page.dart';
import 'package:iris/features/scenario_playback/view/coordinator/scenario_browser.dart';
import 'package:iris/features/scenario_playback/view/coordinator/scenario_browser_store.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/widgets/popup.dart';

/// The independent search page (F-001…F-010), rendered as a whole-interface
/// replacement from both the media-library and the scenario browser.
///
/// Mirrors [ScenarioPreviewPage]'s instant-generate / destroy-restore
/// mechanism: the entry seeds live in [SearchBrowserStore] (read once here);
/// back/Home/Close destroy the page and restore the previous interface
/// (F-002). The search page itself never enters the controller search state
/// (v5-D4) — the inline bar occupies the breadcrumb slot via `headerOverride`.
class MediaSearchPage extends HookWidget {
  final PopupDirection direction;
  final void Function(BuildContext context)? onExit;
  final bool embeddedInStoragesDb;

  /// True when this page belongs to a `modeQueueOverride` browser (floating
  /// queue popup / docked panel). Never read the global
  /// [ScenarioBrowserStore.queueOverrideActive] here: a concurrently-mounted
  /// dock would otherwise hijack the search's routing.
  final bool queueOverride;

  const MediaSearchPage({
    super.key,
    required this.direction,
    this.onExit,
    this.embeddedInStoragesDb = false,
    this.queueOverride = false,
  });

  @override
  Widget build(BuildContext context) {
    final searchStore = useMediaLibSearchStore();
    final browserStore = useSearchBrowserStore();
    final searchContext = browserStore.searchContext;

    final dataSource = useMemoized(
      () {
        // v11-D4: a parked session (Close/Home) resumes the exact page —
        // query + page + results live in the data source instance. v6-D3: a
        // stale parked session (SystemPlaying overridden since creation) is
        // discarded inside `takeParkedSession` — build NOTHING here so the old
        // results never render; the stale effect below degrades to the
        // SystemPlaying scenario page.
        final parked = browserStore.takeParkedSession();
        if (parked != null) return parked;
        if (browserStore.parkedWasStale) return null;
        return searchContext == null
            ? null
            : MediaSearchDataSource(
                searchContext: searchContext,
                queueOverride: queueOverride,
              );
      },
      [searchContext, queueOverride],
    );
    // v6-D4: a one-shot "parked session was stale" marker — the previous
    // resume attempt discarded a session whose SystemPlaying workspace was
    // overridden, so the old search results must NOT be shown. Degrade the
    // back-arrow behavior: land on the SystemPlaying scenario page showing the
    // CURRENT explicit items. Consumed outside the build phase.
    useEffect(() {
      if (!browserStore.consumeParkedStale()) return null;
      openSystemPlayingScenarioPage();
      return null;
    }, const []);
    // v15-D5: a STABLE controller instance — `PaginatedBrowserPage` would
    // otherwise create a fresh `PaginatedBrowserController()` on every build,
    // wiping the selection state the moment `enterSelectionMode` notifies.
    final controller = useMemoized(
      () => PaginatedBrowserController<SearchResultItem>(),
      const [],
    );
    useEffect(() {
      return () {
        // Keep a parked session alive for a later resume; dispose any other
        // instance. destroySearch() already disposes on Back — the data source
        // guards against double-dispose.
        if (!identical(browserStore.parkedSearchSession, dataSource)) {
          dataSource?.dispose();
        }
      };
    }, [dataSource]);

    useListenable(dataSource);
    useListenable(controller);

    // Entering multi-select while virtual merged groups are present shows a
    // one-shot, permanently dismissable hint (non-playback ops unsupported).
    useEffect(() {
      if (!controller.isSelectionMode || dataSource == null) return null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        dataSource.maybeShowVirtualSelectionHint(context);
      });
      return null;
    }, [controller.isSelectionMode, dataSource]);

    useEffect(() {
      if (dataSource == null) return null;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await searchStore.initialized;
        // A resumed session already holds the current page/results — skip the
        // initial fetch so the page number survives close/reopen (v11-D4).
        if (browserStore.consumeWasParked()) return;
        dataSource.fetchPage(0, searchStore.state.pageSize);
      });
      return null;
    }, [dataSource]);

    if (searchContext == null || dataSource == null) {
      return const SizedBox.shrink();
    }

    void handleClose() {
      // v13-D1: Close parks the session AND closes the whole storagedb popup
      // (onExit-or-pop, mirroring the scenario pages' _close). The browser
      // openMode stays `search`, so reopening the popup resumes the session.
      dataSource.parkSearch();
      final exit = onExit;
      if (exit != null) {
        exit(context);
      } else {
        Navigator.of(context).pop();
      }
    }

    void handleHome() {
      // v12-D1: Home behaves like Back — it destroys the session (fresh empty
      // search next time), only Close parks. Capture the return mode before
      // clearAll nulls it, then land on the storagedb tabs main interface.
      // Queue entry (potlike) returns to the playing queue, not the scenario tab.
      final sb = useSearchBrowserStore();
      final isScenario = sb.scenarioSearchReturnMode != null;
      final isQueue = sb.scenarioSearchReturnMode == ScenarioBrowserMode.queue;
      sb.destroySession();
      sb.clearAll();
      if (isQueue) {
        final browser = useScenarioBrowserStore();
        if (queueOverride) {
          // Queue-override panel (floating popup / dock): land back on the
          // queue IN PLACE — no persisted-mode write, no route replacement.
          browser.setQueueOverrideMode(ScenarioBrowserMode.queue);
        } else {
          browser.setMode(ScenarioBrowserMode.queue);
        }
        return;
      }
      if (isScenario) {
        goToScenarioTab(context, direction,
            embedded: embeddedInStoragesDb, queueOverride: queueOverride);
      } else {
        useMediaLibBrowserStore().closeBrowser();
      }
    }

    // v7-D1 (方案 Y): the search page lives in a bottom-aligned Popup and the
    // Flutter view does not auto-resize for the IME; keyboardAware lifts only
    // the search-bar slot above the keyboard and removes the bottom toolbar
    // while typing (space released to the content). No inset (desktop / no
    // keyboard) → unchanged layout.
    return PaginatedBrowserPage<SearchResultItem>(
      dataSource: dataSource,
      controller: controller,
      onHomePage: handleHome,
      onClose: handleClose,
      showHomePage: true,
      showBackButton: true,
      headerOverride: MediaSearchBar(dataSource: dataSource),
      keyboardAware: true,
      emptyStateOverride: Center(
        child: Text(
          dataSource.isEmptyQuery
              ? getLocalizations(context).search_empty_type
              : getLocalizations(context).search_empty_no_match,
          style: const TextStyle(color: Colors.grey),
        ),
      ),
    );
  }
}

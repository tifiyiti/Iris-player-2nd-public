import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/media_library/search/data_source/media_search_data_source.dart';
import 'package:iris/features/media_library/search/model/search_context.dart';
import 'package:iris/features/media_library/store/browser_open_mode.dart';
import 'package:iris/features/scenario_playback/view/coordinator/scenario_browser_store.dart';
import 'package:iris/features/scenario_playback/view/sources/paged_scenario_sources_data_source.dart';

/// Dummy state of the ephemeral [SearchBrowserStore] — seeds are plain mutable
/// fields read once and never trigger reactive `set`.
class SearchBrowserState {
  const SearchBrowserState();
}

/// One-shot snapshot of the scenario browse position so back from the search
/// page restores the exact drilled-in path and breadcrumbs (v5-D1 / v6-D2).
class BrowseReturnPosition {
  final String storageId;

  /// null = browse at the storage root (children list of the storage).
  final String? parentPath;
  final List<String> crumbTail;
  final int baseSegmentCount;

  /// The Layer-2 entry seed path of the browse session (`_seedPath`) — back at
  /// this path returns to the sources list instead of walking up (v6-D2).
  final String? seedPath;

  /// Whether the browse session was entered from a Layer-1 seed
  /// (`_seeded`) — preserved so back-at-root behavior is unchanged.
  final bool seeded;

  const BrowseReturnPosition({
    required this.storageId,
    this.parentPath,
    required this.crumbTail,
    required this.baseSegmentCount,
    this.seedPath,
    this.seeded = false,
  });
}

/// Ephemeral (non-persisted) seeds of the search page — one-shot, cleared on
/// exit (O7: always clear all seeds before setting the target, and clear on
/// leaving the search page). Mirrors [ScenarioBrowserStore]'s seed pattern.
class SearchBrowserStore extends Store<SearchBrowserState> {
  SearchBrowserStore() : super(const SearchBrowserState());

  /// Snapshot of the entry context (lib or scenario).
  SearchContext? searchContext;

  /// Media-library return seed: the open mode to restore (= libContent).
  BrowserOpenMode? mediaLibSearchReturnMode;

  /// Scenario return seed: the browser mode to restore (sources / browse).
  ScenarioBrowserMode? scenarioSearchReturnMode;

  /// Scenario sources position snapshot (v5-D1).
  int? sourcesReturnPage;
  List<ScenarioManageGroup>? sourcesReturnGroupOrder;
  Set<ScenarioManageGroup>? sourcesReturnHiddenGroups;

  /// Scenario browse position snapshot (v5-D1 / v6-D2).
  BrowseReturnPosition? browseReturnPosition;

  /// App-lifetime (in-memory) parked search session (v11-D4): the live
  /// [MediaSearchDataSource] kept alive across Close (X) / Home so reopening
  /// the search page resumes the exact page (query + page + results). Back
  /// destroys it; a full app restart discards it.
  ///
  /// Deliberately NOT cleared by [clearAll] — the session is orthogonal to the
  /// one-shot entry seeds.
  MediaSearchDataSource? parkedSearchSession;

  /// Whether the current page-mounted session was resumed from a parked one —
  /// consumed once by the page to skip the initial `fetchPage(0)` so the page
  /// number survives close/reopen (v11-D4).
  bool _sessionWasParked = false;

  /// v6-D3: true when the last [takeParkedSession] discarded a stale parked
  /// session (the SystemPlaying workspace was overridden after it was created)
  /// — consumed once by the page to degrade to the SystemPlaying scenario page
  /// instead of resuming the stale search results.
  bool _parkedSessionWasStale = false;

  /// In-memory "pin" (v11-D3): when true, tap-play / override-play KEEP the
  /// search page open; when false (default every app launch) they destroy it.
  /// Append always keeps the page open regardless. Not persisted.
  bool pinned = false;

  /// Sets the media-library entry seeds (clearing everything first).
  void setMediaLibEntry(SearchContext context) {
    clearAll();
    searchContext = context;
    mediaLibSearchReturnMode = BrowserOpenMode.libContent;
  }

  /// Sets the scenario sources entry seeds.
  void setScenarioSourcesEntry({
    required SearchContext context,
    required int returnPage,
    required List<ScenarioManageGroup> groupOrder,
    required Set<ScenarioManageGroup> hiddenGroups,
  }) {
    clearAll();
    searchContext = context;
    scenarioSearchReturnMode = ScenarioBrowserMode.sources;
    sourcesReturnPage = returnPage;
    sourcesReturnGroupOrder = List.of(groupOrder);
    sourcesReturnHiddenGroups = Set.of(hiddenGroups);
  }

  /// Sets the scenario browse entry seeds (root browse falls back to
  /// allSources with no position to restore).
  void setScenarioBrowseEntry({
    required SearchContext context,
    BrowseReturnPosition? position,
  }) {
    clearAll();
    searchContext = context;
    scenarioSearchReturnMode = ScenarioBrowserMode.browse;
    browseReturnPosition = position;
  }

  /// Sets the scenario queue entry seeds (same sources as sourcesRoot, but
  /// return target is the playing queue page).
  void setScenarioQueueEntry({required SearchContext context}) {
    clearAll();
    searchContext = context;
    scenarioSearchReturnMode = ScenarioBrowserMode.queue;
  }

  /// Consumes the scenario-sources return position (read once by the returning
  /// sources page) and clears all seeds. Returns null when not returning.
  PagedScenarioSourcesRestore? consumeSourcesRestore() {
    if (scenarioSearchReturnMode != ScenarioBrowserMode.sources) return null;
    final restore = PagedScenarioSourcesRestore(
      page: sourcesReturnPage ?? 0,
      groupOrder: sourcesReturnGroupOrder,
      hiddenGroups: sourcesReturnHiddenGroups,
    );
    clearAll();
    return restore;
  }

  /// Consumes the scenario-browse return position (read once by the returning
  /// browse page) and clears all seeds. Returns null when not returning.
  BrowseReturnPosition? consumeBrowseRestore() {
    if (scenarioSearchReturnMode != ScenarioBrowserMode.browse) return null;
    final position = browseReturnPosition;
    clearAll();
    return position;
  }

  /// Clears every seed (called on search-page exit).
  void clearAll() {
    searchContext = null;
    mediaLibSearchReturnMode = null;
    scenarioSearchReturnMode = null;
    sourcesReturnPage = null;
    sourcesReturnGroupOrder = null;
    sourcesReturnHiddenGroups = null;
    browseReturnPosition = null;
  }

  // ── Search session (v11-D4) & pin (v11-D3) ──

  /// Parks the live data source for a later resume (Close / Home). The page's
  /// dispose guard checks [parkedSearchSession] so the parked instance is NOT
  /// disposed when the page widget is torn down.
  void parkSession(MediaSearchDataSource dataSource) {
    parkedSearchSession = dataSource;
  }

  /// Takes the parked session (if any), marking it as resumed so the page
  /// skips the initial `fetchPage(0)`.
  ///
  /// v6-D3: when the parked session's SystemPlaying workspace was overridden
  /// since creation ([MediaSearchDataSource.isStaleByWorkspaceOverride]) the
  /// session is discarded — its cached results no longer reflect the playing
  /// queue. The "was parked" marker is NOT set (the next open is a fresh
  /// search that must run its initial fetch); the stale marker is set instead.
  MediaSearchDataSource? takeParkedSession() {
    final ds = parkedSearchSession;
    parkedSearchSession = null;
    if (ds != null) {
      if (ds.isStaleByWorkspaceOverride) {
        ds.dispose();
        _parkedSessionWasStale = true;
        return null;
      }
      _sessionWasParked = true;
    }
    return ds;
  }

  /// Consumes the "was parked" marker once (page initial-fetch decision).
  bool consumeWasParked() {
    final was = _sessionWasParked;
    _sessionWasParked = false;
    return was;
  }

  /// Consumes the "parked session was stale" marker once (v6-D3) — the page
  /// degrades to the SystemPlaying scenario page instead of resuming the stale
  /// search.
  bool consumeParkedStale() {
    final was = _parkedSessionWasStale;
    _parkedSessionWasStale = false;
    return was;
  }

  /// Non-consuming read of the stale marker — lets the page skip building a
  /// fresh data source right after a stale resume (the consume happens in the
  /// navigation effect).
  bool get parkedWasStale => _parkedSessionWasStale;

  /// Destroys the parked session (Back / explicit navigation away): disposes
  /// the data source and resets the pin so the next open is a fresh search.
  void destroySession() {
    parkedSearchSession?.dispose();
    parkedSearchSession = null;
    pinned = false;
  }

  void setPinned(bool value) => pinned = value;
}

SearchBrowserStore useSearchBrowserStore() => create(() => SearchBrowserStore());

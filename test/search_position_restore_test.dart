import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/search/model/search_context.dart';
import 'package:iris/features/media_library/search/model/search_scope.dart';
import 'package:iris/features/media_library/search/store/search_browser_store.dart';
import 'package:iris/features/media_library/store/browser_open_mode.dart';
import 'package:iris/features/scenario_playback/view/coordinator/scenario_browser_store.dart';
import 'package:iris/features/scenario_playback/view/sources/paged_scenario_sources_data_source.dart';

void main() {
  group('SearchBrowserStore seeds (F-002 / O7 / v6-D2)', () {
    test('setMediaLibEntry clears stale seeds first (O7)', () {
      final store = SearchBrowserStore();
      // stale seeds from a previous scenario entry
      store.setScenarioBrowseEntry(
        context: const SearchContext(entryContext: SearchEntryContext.scenarioBrowse),
        position: null,
      );
      expect(store.scenarioSearchReturnMode, ScenarioBrowserMode.browse);

      store.setMediaLibEntry(
        const SearchContext(entryContext: SearchEntryContext.libPathTreeDir),
      );
      expect(store.mediaLibSearchReturnMode, BrowserOpenMode.libContent);
      expect(store.scenarioSearchReturnMode, isNull);
      expect(store.browseReturnPosition, isNull);
      expect(store.searchContext!.entryContext,
          SearchEntryContext.libPathTreeDir);
    });

    test('consumeSourcesRestore returns the position once and clears all', () {
      final store = SearchBrowserStore();
      store.setScenarioSourcesEntry(
        context: const SearchContext(
            entryContext: SearchEntryContext.scenarioSourcesRoot),
        returnPage: 3,
        groupOrder: const [
          ScenarioManageGroup.dirSources,
          ScenarioManageGroup.itemSources,
        ],
        hiddenGroups: const {ScenarioManageGroup.dirExclude},
      );
      final restore = store.consumeSourcesRestore();
      expect(restore, isNotNull);
      expect(restore!.page, 3);
      expect(restore.groupOrder!.first, ScenarioManageGroup.dirSources);
      expect(restore.hiddenGroups!.contains(ScenarioManageGroup.dirExclude),
          isTrue);
      expect(store.searchContext, isNull);
      expect(store.sourcesReturnPage, isNull);
      // second consume returns null (already cleared)
      expect(store.consumeSourcesRestore(), isNull);
    });

    test('consumeBrowseRestore preserves seedPath + seeded (v6-D2)', () {
      final store = SearchBrowserStore();
      store.setScenarioBrowseEntry(
        context: const SearchContext(
            entryContext: SearchEntryContext.scenarioBrowse,
            storageId: 's',
            parentPath: 'a/b'),
        position: const BrowseReturnPosition(
          storageId: 's',
          parentPath: 'a/b',
          crumbTail: ['b'],
          baseSegmentCount: 1,
          seedPath: 'a',
          seeded: true,
        ),
      );
      final pos = store.consumeBrowseRestore();
      expect(pos, isNotNull);
      expect(pos!.seedPath, 'a');
      expect(pos.seeded, isTrue);
      expect(pos.parentPath, 'a/b');
      expect(pos.crumbTail, ['b']);
      expect(store.browseReturnPosition, isNull);
      expect(store.consumeBrowseRestore(), isNull);
    });

    test('clearAll wipes every seed', () {
      final store = SearchBrowserStore();
      store.setScenarioBrowseEntry(
        context: const SearchContext(entryContext: SearchEntryContext.scenarioBrowse),
        position: null,
      );
      store.clearAll();
      expect(store.searchContext, isNull);
      expect(store.mediaLibSearchReturnMode, isNull);
      expect(store.scenarioSearchReturnMode, isNull);
      expect(store.browseReturnPosition, isNull);
      expect(store.sourcesReturnPage, isNull);
    });
  });
}

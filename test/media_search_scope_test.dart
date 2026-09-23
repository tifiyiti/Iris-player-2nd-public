import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/search/data_source/media_search_data_source.dart';
import 'package:iris/features/media_library/search/model/search_context.dart';
import 'package:iris/features/media_library/search/model/search_scope.dart';

void main() {
  SearchContext ctx(
    SearchEntryContext e, {
    String? storageId,
    String? parentPath,
  }) =>
      SearchContext(
        entryContext: e,
        storageId: storageId,
        parentPath: parentPath,
      );

  group('defaultScopeFor (§2.3)', () {
    test('no-location contexts always fall back to allSources', () {
      const entries = [
        SearchEntryContext.libPathTreeRoot,
        SearchEntryContext.libAllMedia,
        SearchEntryContext.libAllDirsL1,
        SearchEntryContext.scenarioSourcesRoot,
      ];
      for (final e in entries) {
        expect(defaultScopeFor(ctx(e), allDirsRecursive: true),
            SearchScope.allSources);
        expect(defaultScopeFor(ctx(e), allDirsRecursive: false),
            SearchScope.allSources);
      }
    });

    test('libPathTreeDir → currentDirRecursive (v5-D5)', () {
      final c = ctx(SearchEntryContext.libPathTreeDir,
          storageId: 's', parentPath: 'a/b');
      expect(defaultScopeFor(c, allDirsRecursive: true),
          SearchScope.currentDirRecursive);
    });

    test('libAllDirsL2 follows the allDirsRecursive switch', () {
      final c = ctx(SearchEntryContext.libAllDirsL2,
          storageId: 's', parentPath: 'a/b');
      expect(defaultScopeFor(c, allDirsRecursive: true),
          SearchScope.currentDirRecursive);
      expect(defaultScopeFor(c, allDirsRecursive: false),
          SearchScope.currentDirDirect);
    });

    test('scenarioBrowse root → allSources (D1)', () {
      expect(defaultScopeFor(ctx(SearchEntryContext.scenarioBrowse),
              allDirsRecursive: true),
          SearchScope.allSources);
    });

    test('scenarioBrowse storage level → currentDirRecursive (v6-D1)', () {
      final c = ctx(SearchEntryContext.scenarioBrowse, storageId: 's');
      expect(defaultScopeFor(c, allDirsRecursive: true),
          SearchScope.currentDirRecursive);
    });

    test('scenarioBrowse concrete path → currentDirRecursive', () {
      final c = ctx(SearchEntryContext.scenarioBrowse,
          storageId: 's', parentPath: 'a/b');
      expect(defaultScopeFor(c, allDirsRecursive: true),
          SearchScope.currentDirRecursive);
    });
  });

  group('SearchContext.hasNoLocation (v4-D4)', () {
    test('true only when both storageId and parentPath are null', () {
      expect(ctx(SearchEntryContext.libPathTreeRoot).hasNoLocation, isTrue);
      expect(ctx(SearchEntryContext.scenarioBrowse, storageId: 's').hasNoLocation,
          isFalse);
      expect(
          ctx(SearchEntryContext.scenarioBrowse,
              storageId: 's', parentPath: 'a').hasNoLocation,
          isFalse);
    });
  });
}

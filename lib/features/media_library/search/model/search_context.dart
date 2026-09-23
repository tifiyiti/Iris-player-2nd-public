import 'package:iris/features/media_library/model/enum/media_lib_sources.dart';
import 'package:iris/features/media_library/search/model/search_scope.dart';

/// A normalized query source of a search (F-007 / §5.1.2 / §5.4).
///
/// [recursive] is the traversal semantics (directory + recursive = prefix,
/// directory + non-recursive = direct children); it is decoupled from the
/// `pathGroupFirst` sort parameter. [scenarioSourceId] is the scenario source
/// row id so source-scoped exclude rules can attach per-branch (v5-D3); lib
/// sources and synthetic current-dir tuples leave it null.
class SearchSource {
  final String storageId;
  final String? path;
  final MediaSourceKind kind;
  final bool recursive;
  final int? scenarioSourceId;

  const SearchSource({
    required this.storageId,
    this.path,
    required this.kind,
    this.recursive = false,
    this.scenarioSourceId,
  });
}

/// A scenario explicit item candidate for in-memory matching (F-007 / §5.4).
class SearchExplicitItem {
  final String storageId;
  final String path;

  const SearchExplicitItem({required this.storageId, required this.path});
}

/// One-shot snapshot of the search entry context, captured when the search
/// page opens and never subscribed to afterwards (§5.4).
class SearchContext {
  final SearchEntryContext entryContext;
  final String? storageId;
  final String? parentPath;
  final String? scenarioId;
  final List<SearchSource> sources;
  final List<SearchExplicitItem> explicitItems;

  const SearchContext({
    required this.entryContext,
    this.storageId,
    this.parentPath,
    this.scenarioId,
    this.sources = const [],
    this.explicitItems = const [],
  });

  /// True when no directory location is available: the currentDir* scopes are
  /// disabled in the scope menu (v4-D4).
  bool get hasNoLocation => storageId == null && parentPath == null;

  /// True when the search was entered from the media library (not a scenario) —
  /// v15-D1 context C. More explicit than `scenarioId == null` because the
  /// entry family is already encoded in [entryContext].
  bool get isMediaLibEntry => switch (entryContext) {
        SearchEntryContext.libPathTreeRoot ||
        SearchEntryContext.libPathTreeDir ||
        SearchEntryContext.libAllMedia ||
        SearchEntryContext.libAllDirsL1 ||
        SearchEntryContext.libAllDirsL2 =>
          true,
        SearchEntryContext.scenarioSourcesRoot ||
        SearchEntryContext.scenarioBrowse ||
        SearchEntryContext.scenarioQueue =>
          false,
      };
}

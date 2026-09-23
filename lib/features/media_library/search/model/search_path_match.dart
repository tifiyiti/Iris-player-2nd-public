import 'package:iris/features/media_library/model/enum/media_lib_sources.dart';
import 'package:iris/features/media_library/search/model/search_context.dart';
import 'package:iris/features/media_library/search/model/search_exclude_rule.dart';
import 'package:iris/features/scenario_playback/model/enum/exclude_rule_kind.dart';
import 'package:iris/features/scenario_playback/model/enum/exclude_scope.dart';
import 'package:iris/utils/path_conv.dart';

/// Pure path-matching helpers shared by the search data source's in-memory
/// explicit-item logic and its tests. Mirrors the DB-side source/rule
/// semantics (§5.1.2 / §5.1.3) so the DB segment and the explicit segment
/// agree on "in scope" and "excluded".

/// Storage-relative parent of a canonical [path], or null at the storage root.
String? parentOf(String canonicalPath) {
  final idx = canonicalPath.lastIndexOf('/');
  return idx < 0 ? null : canonicalPath.substring(0, idx);
}

/// Whether the file at [path] in [storageId] is covered by [source].
///
/// Mirrors the DAO source predicate: storage → whole storage; file → exact;
/// directory recursive → exact-or-prefix; directory non-recursive → direct
/// children (storage root '' → parentPath == null).
bool sourceCovers(SearchSource source, String storageId, String path) {
  if (source.storageId != storageId) return false;
  final canonical = canonicalDbPath(path);
  final srcPath = source.path == null ? '' : canonicalDbPath(source.path!);
  switch (source.kind) {
    case MediaSourceKind.storage:
      return true;
    case MediaSourceKind.file:
      return canonical == srcPath;
    case MediaSourceKind.directory:
      if (source.recursive) {
        if (srcPath.isEmpty) return true;
        return canonical == srcPath || canonical.startsWith('$srcPath/');
      }
      final parent = parentOf(canonical);
      if (srcPath.isEmpty) return parent == null;
      return parent == srcPath;
  }
}

/// Whether any source in [sources] covers the file (F-007 "scope 内").
bool anySourceCovers(
    List<SearchSource> sources, String storageId, String path) {
  return sources.any((s) => sourceCovers(s, storageId, path));
}

/// Whether a scenario-scoped exclude rule prunes the file (explicit items only
/// respond to scenario-scoped rules; source-scoped never prune them, v5-D3).
bool explicitExcludedByScenarioRules(
  List<SearchExcludeRule> rules,
  String storageId,
  String path,
) {
  final canonical = canonicalDbPath(path);
  for (final rule in rules) {
    if (rule.scope != ExcludeScope.scenario) continue;
    if (rule.storageId != storageId) continue;
    final rulePath = canonicalDbPath(rule.path);
    if (rule.kind == ExcludeRuleKind.media) {
      if (rulePath == canonical) return true;
    } else {
      // directory rule
      if (rulePath.isEmpty) return true; // storage-root exclude prunes all
      if (rule.recursive) {
        if (canonical == rulePath || canonical.startsWith('$rulePath/')) {
          return true;
        }
      } else {
        if (parentOf(canonical) == rulePath) return true;
      }
    }
  }
  return false;
}

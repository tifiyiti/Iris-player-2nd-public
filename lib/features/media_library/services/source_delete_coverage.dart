import 'package:iris/utils/path_conv.dart';

/// What a source deletion should do with the media-node rows it referenced.
///
/// Nodes are **scope-owned** (shared across every entry linked into the same
/// data scope), so a source's path range may still be needed after its row is
/// removed:
///  * an ancestor, equal, or full-storage sibling source covers the range;
///  * a descendant sibling source needs a subset of it.
/// In both cases the rows must survive; only when nothing else references the
/// range may they be dropped.
enum SourceDeleteNodeAction {
  /// Keep every node row — another surviving source still needs the range.
  keep,

  /// Drop the file/dir rows at or below the deleted source's path.
  deleteRange,

  /// Drop every node row of the storage (the deleted source covered all of it).
  deleteStorage,
}

/// Decides the node action for deleting one source, given the paths of every
/// OTHER source that shares the same data scope (across libraries).
///
/// [siblingPaths] entries are raw persisted path strings; `null`/empty means a
/// full-storage source. Both sides are canonicalized before comparison so
/// differing leading-slash conventions never hide an overlap.
SourceDeleteNodeAction resolveSourceDeleteNodeAction({
  required String sourcePath,
  required Iterable<String?> siblingPaths,
}) {
  final path = canonicalDbPath(sourcePath);
  var hasDescendant = false;

  for (final raw in siblingPaths) {
    // A full-storage sibling covers everything.
    if (raw == null || raw.isEmpty) return SourceDeleteNodeAction.keep;
    final sp = canonicalDbPath(raw);
    // Equal range → covered.
    if (sp == path) return SourceDeleteNodeAction.keep;
    // Sibling is an ANCESTOR of the deleted range → it fully covers it.
    // (The reverse — a descendant — only covers a subset, handled below.)
    if (path.isNotEmpty && path.startsWith('$sp/')) {
      return SourceDeleteNodeAction.keep;
    }
    // Sibling is a DESCENDANT: it needs this range's rows, so keep them.
    if (path.isEmpty || sp.startsWith('$path/')) {
      hasDescendant = true;
    }
  }

  if (hasDescendant) return SourceDeleteNodeAction.keep;
  return path.isEmpty
      ? SourceDeleteNodeAction.deleteStorage
      : SourceDeleteNodeAction.deleteRange;
}

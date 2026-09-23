/// Pure breadcrumb helpers, computed in real-time from navigation state.
///
/// The source of truth for navigation lives in the stores (current path /
/// storage / parent path); these helpers only derive display segments from it
/// and never cache the result.
library;

/// Breadcrumb segments of a storage-relative [path] below [basePath].
/// Returns the segments past the base, empty when at/above the base.
List<String> pathBreadcrumbs({
  required List<String> path,
  required List<String> basePath,
}) {
  if (path.length <= basePath.length) return const [];
  return path.sublist(basePath.length);
}

/// Sealed breadcrumb segments: the base path is closed into one tile named
/// [sealedName] (storage / lib source / scenario seed name) so mount prefixes
/// like `storage / emulated / 0` never leak as separate crumbs.
List<String> sealedPathBreadcrumbs({
  required String sealedName,
  required List<String> path,
  required List<String> basePath,
}) {
  return <String>[
    sealedName,
    ...pathBreadcrumbs(path: path, basePath: basePath),
  ];
}

/// Absolute segment length a sealed crumb [crumbIndex] maps to.
/// Index 0 is the sealed root itself ([baseLength]); deeper crumbs add one
/// segment each. Multi-segment bases must use this instead of `index + 1`.
int sealedCrumbTarget({
  required int baseLength,
  required int crumbIndex,
}) {
  return baseLength + crumbIndex;
}

/// Library content breadcrumbs: `Sources` + storage name + relative segments.
List<String> contentBreadcrumbs({
  required String? storageName,
  required String? parentPath,
  required String? sourceRoot,
}) {
  final crumbs = <String>['Sources'];
  if (storageName != null && storageName.isNotEmpty) {
    crumbs.add(storageName);
  }
  if (parentPath != null && parentPath.isNotEmpty) {
    String relative = parentPath;
    final root = sourceRoot ?? '';
    if (root.isNotEmpty && parentPath.startsWith('$root/')) {
      relative = parentPath.substring(root.length + 1);
    } else if (parentPath == root || root.isEmpty) {
      // No sealed root known: only the leaf name is safe to show, never the
      // absolute path segments (no `emulated / 0` leak).
      final segs =
          parentPath.split('/').where((s) => s.isNotEmpty).toList();
      relative = segs.isEmpty ? '' : segs.last;
    } else {
      // Prefix mismatch (stale/foreign path): fall back to the sealed root
      // only instead of leaking the full absolute path.
      relative = '';
    }
    if (relative.isNotEmpty) {
      crumbs.addAll(relative.split('/').where((s) => s.isNotEmpty));
    }
  }
  return crumbs;
}

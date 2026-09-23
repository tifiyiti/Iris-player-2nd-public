/// Throttle + equality policy for the manager page's pinned-shortcut query.
///
/// `queryPinned` crosses a platform channel into `ShortcutManager` (Binder IPC
/// on phones), so the manager page must NOT poll it. It refreshes only on
/// mount, on app-resume, on editor return, and on explicit manual refresh —
/// and even then only when this policy says the query is worthwhile.
///
/// Kept as pure statics so the contract is unit-testable without widgets,
/// channels, or the wall clock.
abstract final class PinnedRefreshPolicy {
  /// Minimum interval between two non-forced platform queries.
  static const int throttleMs = 2000;

  /// Whether a platform query is worthwhile right now.
  ///
  /// [force] (mount, manual refresh, editor return) bypasses the throttle
  /// window but still respects the hard guards: an in-flight query, a
  /// non-Android host, an obscured route (editor sheet on top), and an empty
  /// entry list never justify a Binder round-trip.
  static bool shouldQuery({
    required bool isRefreshing,
    required bool isAndroid,
    required bool isRouteCurrent,
    required bool hasEntries,
    required int nowMs,
    required int lastQueryMs,
    required bool force,
    int throttleMs = PinnedRefreshPolicy.throttleMs,
  }) {
    if (isRefreshing) return false;
    if (!isAndroid) return false;
    if (!isRouteCurrent) return false;
    if (!hasEntries) return false;
    if (!force && nowMs - lastQueryMs < throttleMs) return false;
    return true;
  }

  /// Order-independent set comparison. The page skips `setState` when the
  /// freshly queried ids equal the rendered ones, so a no-change resume
  /// costs zero list rebuilds.
  static bool isSameSet(Set<String> a, Set<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    return a.containsAll(b);
  }
}

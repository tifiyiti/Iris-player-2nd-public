/// Gates live-seek emission during a scrub drag to at most one seek per
/// [minInterval], so continuous dragging does not flood the player backend.
///
/// Pure clock-injected logic: unit-testable without widgets or fake players.
/// Shared by every scrub surface (one-handed scrubbers, the linear control-bar
/// slider, the full-screen gesture layers) so a drag behaves identically
/// wherever it starts.
class LiveSeekThrottle {
  LiveSeekThrottle({this.minInterval = const Duration(milliseconds: 120)});

  final Duration minInterval;

  DateTime? _lastAllowed;

  /// Returns true when a live seek should be emitted now; records the stamp.
  bool allow(DateTime now) {
    final DateTime? last = _lastAllowed;
    if (last != null && now.difference(last) < minInterval) return false;
    _lastAllowed = now;
    return true;
  }

  /// Re-arms immediately (new drag session).
  void reset() => _lastAllowed = null;
}

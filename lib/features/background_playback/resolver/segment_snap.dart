import 'package:iris/features/background_playback/model/domain/background_mapping.dart';

/// Snap-to-saved-boundary (卡值) math for the APB align editor.
///
/// The saved content boundaries the foreground axis draws (the activation-order
/// winners) become temporary walls for the A / P / B handles: a moving point
/// stops exactly at a wall instead of passing, the way it already stops at the
/// 0% / 100% media ends. Unlike media ends, a wall is NOT permanent: once a
/// gesture hits a wall, the gesture still stops there, but the wall is marked
/// for release — the NEXT gesture passes it freely both ways. Hitting a new
/// wall marks that one; the memory keeps only the most recent N releases, so
/// an evicted wall blocks again.
abstract final class SegmentSnap {
  /// Default number of released walls remembered.
  static const int kDefaultReleaseLimit = 1;

  /// Smallest number of released walls remembered.
  static const int kMinReleaseLimit = 1;

  /// Largest number of released walls remembered.
  static const int kMaxReleaseLimit = 10000;

  /// Usable walls from the fg-drawn winners: every resolved slice edge except
  /// the 0 / 100% media ends (those never generate snap values). Deduped and
  /// sorted ascending.
  static List<int> wallsFromSlices(
    List<MappingSegment> slices, {
    required int fgDurMs,
  }) {
    final set = <int>{};
    for (final s in slices) {
      if (s.fgStartMs > 0 && s.fgStartMs < fgDurMs) set.add(s.fgStartMs);
      if (s.fgEndMs > 0 && s.fgEndMs < fgDurMs) set.add(s.fgEndMs);
    }
    return set.toList()..sort();
  }

  /// Clamps the scalar [desired] (A, P-centre or B, in fg ms) to the first
  /// non-[released] wall crossed from [previous].
  ///
  /// Walking past a released wall never stops, and neither does a move that
  /// reaches back to, or away from, the wall the point already sits on. The
  /// returned [SnapClampResult.hit] is the wall that blocked (null = free).
  static SnapClampResult clampScalar({
    required int from,
    required int desired,
    required List<int> walls,
    required Set<int> released,
  }) {
    if (desired == from) return SnapClampResult(desired, null);
    // The [from] end is EXCLUSIVE (a point already sitting on a wall moves
    // off it freely); the [desired] end is inclusive (reaching a wall stops
    // and records the hit).
    if (desired > from) {
      for (final w in walls) {
        if (released.contains(w)) continue;
        if (w > from && w <= desired) return SnapClampResult(w, w);
      }
    } else {
      for (final w in walls.reversed) {
        if (released.contains(w)) continue;
        if (w < from && w >= desired) return SnapClampResult(w, w);
      }
    }
    return SnapClampResult(desired, null);
  }
}

/// Outcome of [SegmentSnap.clampScalar].
class SnapClampResult {
  const SnapClampResult(this.value, this.hit);

  /// The value the handle may take (the wall when blocked).
  final int value;

  /// The wall that blocked, or null when the move was free.
  final int? hit;
}

/// One handle gesture under snap: feeds [advance] the live scalar per tick.
///
/// A wall hit mid-gesture keeps blocking that gesture (pushing further in the
/// same direction stays on it), while reversing off is always free and may hit
/// again. Released walls never block. [hits] is the ordered, deduped record
/// the host commits to the [SegmentSnapMemory] on tap-up.
class SnapDragSession {
  SnapDragSession({required this.walls, required this.released});

  final List<int> walls;
  final Set<int> released;

  int? _holdWall;
  int _holdDir = 0;
  final List<int> _hits = [];

  List<int> get hits => List.unmodifiable(_hits);

  SnapClampResult advance({required int from, required int desired}) {
    if (desired == from) return SnapClampResult(desired, null);
    final dir = (desired - from).sign;
    // Still pressing into the wall hit earlier in this gesture: stay on it.
    // (A wall released before the gesture started can never be held.)
    if (_holdWall != null &&
        from == _holdWall &&
        dir == _holdDir &&
        !released.contains(_holdWall)) {
      _note(_holdWall!);
      return SnapClampResult(_holdWall!, _holdWall);
    }
    // Reversing off, standing still elsewhere, or jumping: drop the hold and
    // clamp normally.
    _holdWall = null;
    _holdDir = 0;
    final r = SegmentSnap.clampScalar(
      from: from,
      desired: desired,
      walls: walls,
      released: released,
    );
    if (r.hit != null) {
      _holdWall = r.hit;
      _holdDir = dir;
      _note(r.hit!);
    }
    return r;
  }

  void _note(int w) {
    if (!_hits.contains(w)) _hits.add(w);
  }
}

/// Session-only memory of which walls a drag released by hitting them.
///
/// Bounded: releasing beyond [capacity] evicts the oldest release, which then
/// blocks again — only the most recent N stays disabled. Never persisted and
/// never part of the draft; the editor clears it on toggle / draft change.
class SegmentSnapMemory {
  SegmentSnapMemory(this.capacity);

  int capacity;

  final List<int> _released = <int>[]; // oldest first

  /// The currently disabled walls (most recent last).
  Set<int> get released => _released.toSet();

  bool isReleased(int wall) => _released.contains(wall);

  /// Marks [wall] released, cancelling the oldest release when over capacity.
  /// Hitting the same wall again just refreshes it (single entry).
  void release(int wall) {
    _released.remove(wall);
    _released.add(wall);
    final cap = capacity < SegmentSnap.kMinReleaseLimit
        ? SegmentSnap.kMinReleaseLimit
        : capacity;
    while (_released.length > cap) {
      _released.removeAt(0);
    }
  }

  void setCapacity(int n) {
    capacity = n;
    final cap = n < SegmentSnap.kMinReleaseLimit
        ? SegmentSnap.kMinReleaseLimit
        : n;
    // Keep only the most recent releases: an evicted wall blocks again.
    while (_released.length > cap) {
      _released.removeAt(0);
    }
  }

  void clear() => _released.clear();
}

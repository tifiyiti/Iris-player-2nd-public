import 'package:iris/features/background_playback/model/domain/background_mapping.dart';

/// How the user resolved a new segment that overlaps existing segments.
enum OverlapChoice {
  /// Clip the NEW segment to the empty space BEFORE the first overlap
  /// (e.g. 10–70 vs existing 30–60 → keep 10–30).
  keepFront,

  /// Clip the NEW segment to the empty space AFTER the last overlap
  /// (e.g. 10–70 vs existing 30–60 → keep 60–70).
  keepBack,

  /// Overwrite: drop the overlapping old segments and keep the full new one.
  overwrite,
}

/// Pure overlap solver for the mapping editor.
///
/// Segments are non-overlapping in the DB (repository enforces); when a new
/// segment collides the UI presents these choices instead of silently
/// overwriting (需求 §25/§26). Returns the segment list to persist.
abstract final class MappingOverlap {
  /// Whether [next] overlaps any segment in [existing] (half-open ranges).
  static bool overlapsAny(
    List<MappingSegment> existing,
    MappingSegment next,
  ) {
    return existing.any((o) =>
        next.fgStartMs < o.fgEndMs && next.fgEndMs > o.fgStartMs);
  }

  /// Existing segments strictly inside [next] (fully covered).
  static List<MappingSegment> coveredBy(
    List<MappingSegment> existing,
    MappingSegment next,
  ) {
    return [
      for (final o in existing)
        if (o.fgStartMs >= next.fgStartMs && o.fgEndMs <= next.fgEndMs) o,
    ];
  }

  /// Applies [choice] to merge [next] into a copy of [existing].
  ///
  /// Returns null when the choice leaves a residual overlap (the UI should
  /// surface it and let the user pick again / cancel).
  static List<MappingSegment>? resolve({
    required List<MappingSegment> existing,
    required MappingSegment next,
    required OverlapChoice choice,
  }) {
    final others = existing
        .where((o) => o.fgEndMs <= next.fgStartMs || o.fgStartMs >= next.fgEndMs)
        .toList();
    final hits = existing
        .where((o) =>
            o.fgStartMs < next.fgEndMs && o.fgEndMs > next.fgStartMs)
        .toList()
      ..sort((a, b) => a.fgStartMs.compareTo(b.fgStartMs));
    if (hits.isEmpty) {
      // No overlap at all — plain insert (sorted below).
      return sorted([...others, next]);
    }
    MappingSegment? kept;
    switch (choice) {
      case OverlapChoice.keepFront:
        final boundary = hits.first.fgStartMs;
        if (boundary <= next.fgStartMs) return null; // nothing left to keep
        kept = _clipFront(next, boundary);
        // Clip only the NEW segment: the existing (hit) segments stay, so
        // 10–70 vs 30–60 becomes 10–30(new) + 30–60(old).
        return _freeOf([...others, ...hits], kept)
            ? sorted([...others, ...hits, kept])
            : null;
      case OverlapChoice.keepBack:
        final boundary = hits.last.fgEndMs;
        if (boundary >= next.fgEndMs) return null;
        kept = _clipBack(next, boundary);
        return _freeOf([...others, ...hits], kept)
            ? sorted([...others, ...hits, kept])
            : null;
      case OverlapChoice.overwrite:
        // Full new segment replaces every overlapping old one.
        return sorted([...others, next]);
    }
  }

  /// Trims [next] so it no longer overlaps any segment in [existing],
  /// preserving the EXISTING segments and emitting the free gaps the new span
  /// still covers (a single overlap yields a left + right residual; straddling
  /// several existing segments yields one residual per gap).
  ///
  /// This is the A-B editor's 「移除本次重叠部分」 choice. A playMedia residual
  /// keeps the 1:1 offset of the draft, so its bg window shifts by the same
  /// amount its fg window did. Returns an empty list when the draft is fully
  /// covered (nothing left to save).
  static List<MappingSegment> splitAroundExisting({
    required List<MappingSegment> existing,
    required MappingSegment next,
  }) {
    final hits = existing
        .where((o) => o.fgStartMs < next.fgEndMs && o.fgEndMs > next.fgStartMs)
        .toList()
      ..sort((a, b) => a.fgStartMs.compareTo(b.fgStartMs));
    if (hits.isEmpty) return [next];

    // Clip every hit to [next]'s window and merge them into disjoint blocked
    // ranges (existing segments never overlap each other, but clipping keeps
    // the loop simple and safe against a caller-supplied unsorted list).
    final blocked = <({int start, int end})>[];
    for (final o in hits) {
      final start = o.fgStartMs < next.fgStartMs ? next.fgStartMs : o.fgStartMs;
      final end = o.fgEndMs > next.fgEndMs ? next.fgEndMs : o.fgEndMs;
      if (start >= end) continue;
      if (blocked.isNotEmpty && start <= blocked.last.end) {
        final last = blocked.removeLast();
        blocked.add((start: last.start, end: end > last.end ? end : last.end));
      } else {
        blocked.add((start: start, end: end));
      }
    }

    final out = <MappingSegment>[];
    var cursor = next.fgStartMs;
    for (final b in blocked) {
      if (b.start > cursor) out.add(_residual(next, cursor, b.start));
      if (b.end > cursor) cursor = b.end;
    }
    if (next.fgEndMs > cursor) out.add(_residual(next, cursor, next.fgEndMs));
    return out;
  }

  /// Clips the fg END of [next] to [boundary], shrinking its bg window by the
  /// same amount (1:1) so the kept span still points at the intended bg
  /// content. A silence draft (null bg window) keeps its nulls.
  static MappingSegment _clipFront(MappingSegment next, int boundary) {
    final bs = next.bgStartMs;
    final be = next.bgEndMs;
    final trim = next.fgEndMs - boundary;
    return next.copyWith(
      fgEndMs: boundary,
      fgEndN: null,
      bgStartN: null,
      bgEndN: null,
      bgEndMs: (bs == null || be == null) ? be : be - trim,
    );
  }

  /// Clips the fg START of [next] to [boundary], shifting its bg window by
  /// the same amount (1:1). A silence draft (null bg window) keeps its nulls.
  static MappingSegment _clipBack(MappingSegment next, int boundary) {
    final bs = next.bgStartMs;
    final be = next.bgEndMs;
    final shift = boundary - next.fgStartMs;
    return next.copyWith(
      fgStartMs: boundary,
      fgStartN: null,
      bgStartN: null,
      bgEndN: null,
      bgStartMs: (bs == null || be == null) ? bs : bs + shift,
    );
  }

  /// Re-windows [next] to [fgStart, fgEnd], shifting its bg window by the same
  /// offset (1:1) so the residual still points at the intended bg content.
  static MappingSegment _residual(
    MappingSegment next,
    int fgStart,
    int fgEnd,
  ) {
    final deltaStart = fgStart - next.fgStartMs;
    final deltaEnd = fgEnd - next.fgStartMs;
    final bs = next.bgStartMs;
    return next.copyWith(
      id: 0,
      fgStartMs: fgStart,
      fgEndMs: fgEnd,
      fgStartN: null,
      fgEndN: null,
      bgStartMs: bs == null ? null : bs + deltaStart,
      bgEndMs: bs == null ? null : bs + deltaEnd,
      bgStartN: null,
      bgEndN: null,
    );
  }

  /// True when [candidate] does not collide with any segment of [others].
  static bool _freeOf(List<MappingSegment> others, MappingSegment candidate) =>
      others.every((o) =>
          candidate.fgStartMs >= o.fgEndMs || candidate.fgEndMs <= o.fgStartMs);

  /// Sorts a persisted candidate list by fgStart (editor display order).
  static List<MappingSegment> sorted(List<MappingSegment> segments) =>
      List<MappingSegment>.of(segments)
        ..sort((a, b) => a.fgStartMs.compareTo(b.fgStartMs));
}

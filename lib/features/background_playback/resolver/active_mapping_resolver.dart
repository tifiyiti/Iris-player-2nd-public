import 'dart:math' as math;

import 'package:iris/features/background_playback/model/domain/background_mapping.dart';
import 'package:iris/features/background_playback/resolver/mapping_binding.dart';
import 'package:iris/features/background_playback/resolver/mapping_overview_math.dart';
import 'package:iris/features/background_playback/resolver/mapping_timeline_math.dart';

/// Single source of truth for "which saved mapping segment is in effect".
///
/// Segments may overlap (v34): the user activates segments one by one and the
/// LARGEST [MappingSegment.activeSeq] wins wherever active segments collide
/// (last-activated-wins — the mapping analogue of the WebDAV default-name lit
/// order). Disabled segments are invisible here. Playback, the manager overview
/// and the editor's foreground axis all resolve through this class so the three
/// can never disagree on a given position.
abstract final class ActiveMappingResolver {
  /// The active segment covering [fgPosMs] (half-open), or null when the
  /// position falls in a gap / on a disabled-only region.
  ///
  /// Precedence: highest [MappingSegment.activeSeq]; ties break on the larger
  /// `fgStartMs`, then the larger id — deterministic even for legacy rows whose
  /// sequence was never assigned.
  static MappingSegment? effectiveAt(
    List<MappingSegment> segments,
    int fgPosMs,
  ) {
    MappingSegment? best;
    for (final s in segments) {
      if (!s.isActive) continue;
      if (fgPosMs < s.fgStartMs || fgPosMs >= s.fgEndMs) continue;
      if (best == null || _wins(s, best)) best = s;
    }
    return best;
  }

  static bool _wins(MappingSegment a, MappingSegment b) {
    if (a.activeSeq != b.activeSeq) return a.activeSeq > b.activeSeq;
    if (a.fgStartMs != b.fgStartMs) return a.fgStartMs > b.fgStartMs;
    return a.id > b.id;
  }

  /// The next activation sequence for a timeline: one past the current maximum
  /// (and at least 1, since 0 is the "unassigned" default).
  static int nextActiveSeq(List<MappingSegment> segments) {
    var max = 0;
    for (final s in segments) {
      if (s.activeSeq > max) max = s.activeSeq;
    }
    return max + 1;
  }

  /// Combines a saved timeline with a freshly committed [next] segment.
  ///
  /// `overwrite` (or [asNew] false) replaces the row the editor was opened on
  /// (matched by [editingId]) and keeps every other row; because a brand-new
  /// draft has id 0 this degrades to an append. `asNew` appends unconditionally
  /// so the new row shadows whatever it overlaps. Nothing is ever deleted, so a
  /// shadowed mapping keeps its saved data — ready to be re-activated later.
  static List<MappingSegment> mergeSegment({
    required List<MappingSegment> all,
    required MappingSegment next,
    required bool asNew,
    required int editingId,
  }) {
    final kept = <MappingSegment>[
      for (final s in all)
        if (asNew || editingId == 0 || s.id != editingId) s,
    ];
    return List<MappingSegment>.of([...kept, next])
      ..sort((a, b) => a.fgStartMs.compareTo(b.fgStartMs));
  }

  /// Segment identity for change/abort tracking. Extends the raw key with the
  /// activation sequence and background identity so two different winners at
  /// the same span are distinct.
  static String segmentKey(MappingSegment s) =>
      '${MappingTimelineMath.segmentKey(s)}|${s.activeSeq}|'
      '${s.bgStorageId}:${s.bgPath}';

  /// Ordered, non-overlapping blocks covering exactly `0..fgTotalMs` that show
  /// ONLY the segment actually in effect on each slice — the complete value of a
  /// shadowed segment never reaches the axis.
  ///
  /// The axis is sliced at every active edge; each atomic slice is classified by
  /// its [effectiveAt] winner (gap when none). A playMedia slice is further
  /// split covered/uncovered by the background file's real window, so a span
  /// longer than its file cannot masquerade as content.
  static List<MappingBlock> visibleBlocks({
    required List<MappingSegment> segments,
    required int fgTotalMs,
  }) {
    if (fgTotalMs <= 0) return const <MappingBlock>[];

    final edges = <int>{0, fgTotalMs};
    for (final s in segments) {
      if (!s.isActive) continue;
      final start = s.fgStartMs.clamp(0, fgTotalMs);
      final end = s.fgEndMs.clamp(0, fgTotalMs);
      if (end <= start) continue;
      edges.add(start);
      edges.add(end);
    }
    final sorted = edges.toList()..sort();

    final out = <MappingBlock>[];
    for (var i = 0; i + 1 < sorted.length; i++) {
      final start = sorted[i];
      final end = sorted[i + 1];
      if (end <= start) continue;
      final winner = effectiveAt(segments, start);
      if (winner == null) {
        _push(out, MappingBlock(
          kind: MappingBlockKind.gap,
          startMs: start,
          endMs: end,
        ));
      } else if (!winner.isPlayMedia) {
        _push(out, MappingBlock(
          kind: MappingBlockKind.silence,
          startMs: start,
          endMs: end,
          segment: winner,
        ));
      } else {
        _pushPlayMedia(out, winner, start, end);
      }
    }
    return out;
  }

  /// Splits a playMedia winner's atomic slice into covered/uncovered parts,
  /// mirroring [MappingOverviewMath]'s window math but confined to the slice.
  static void _pushPlayMedia(
    List<MappingBlock> out,
    MappingSegment s,
    int start,
    int end,
  ) {
    final total = MappingTimelineMath.bgTotalMsFromNorms(s);
    if (total == null || total <= 0) {
      _push(out, MappingBlock(
          kind: MappingBlockKind.covered, startMs: start, endMs: end, segment: s));
      return;
    }
    final off = MappingBinding.offsetMsOf(s);
    final cStart = math.max(start, math.min(end, math.max(-off, 0)));
    final cEnd = math.max(start, math.min(end, total - off));
    if (cEnd <= cStart) {
      _push(out, MappingBlock(
          kind: MappingBlockKind.uncovered, startMs: start, endMs: end, segment: s));
      return;
    }
    if (cStart > start) {
      _push(out, MappingBlock(
          kind: MappingBlockKind.uncovered, startMs: start, endMs: cStart, segment: s));
    }
    _push(out, MappingBlock(
        kind: MappingBlockKind.covered, startMs: cStart, endMs: cEnd, segment: s));
    if (end > cEnd) {
      _push(out, MappingBlock(
          kind: MappingBlockKind.uncovered, startMs: cEnd, endMs: end, segment: s));
    }
  }

  /// Appends [block], merging it into the previous block when they are adjacent
  /// and belong to the same kind AND the same segment (a disabled neighbour's
  /// edge must not shatter a slice into invisible seams; two different files
  /// keep their own colour and stay separate).
  static void _push(List<MappingBlock> out, MappingBlock block) {
    if (out.isNotEmpty) {
      final prev = out.last;
      if (prev.kind == block.kind &&
          prev.endMs == block.startMs &&
          _sameSegment(prev.segment, block.segment)) {
        out[out.length - 1] = MappingBlock(
          kind: prev.kind,
          startMs: prev.startMs,
          endMs: block.endMs,
          segment: prev.segment,
        );
        return;
      }
    }
    out.add(block);
  }

  static bool _sameSegment(MappingSegment? a, MappingSegment? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    if (a.id != 0 && b.id != 0) return a.id == b.id;
    return a.fgStartMs == b.fgStartMs && a.fgEndMs == b.fgEndMs;
  }
}

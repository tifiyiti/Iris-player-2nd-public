import 'package:iris/features/background_playback/model/domain/background_mapping.dart';
import 'package:iris/features/background_playback/resolver/active_mapping_resolver.dart';

/// What a slice of the Level-2 foreground axis represents.
enum MappingBlockKind {
  /// No segment covers this span.
  gap,

  /// A `silence` segment (bg intentionally muted, no file).
  silence,

  /// A `playMedia` segment span that the background file actually covers.
  covered,

  /// A `playMedia` segment span the background file does NOT cover (bg starts
  /// late, or has already run out) — drawn gray so it never masquerades as
  /// content and cannot visually merge with a neighbouring file's window.
  uncovered,
}

/// One slice of the foreground axis, [startMs]..[endMs], already clipped to the
/// foreground duration by [MappingOverviewMath.layout].
class MappingBlock {
  const MappingBlock({
    required this.kind,
    required this.startMs,
    required this.endMs,
    this.segment,
  });

  final MappingBlockKind kind;
  final int startMs;
  final int endMs;
  final MappingSegment? segment;

  int get lengthMs => endMs - startMs;

  @override
  String toString() => 'MappingBlock(${kind.name}, $startMs..$endMs)';
}

/// Pure layout of the manager's 0–100% overview axis.
///
/// The axis IS the foreground duration; every block is a fraction of it. Gaps
/// and the uncovered parts of a playMedia segment are explicit blocks so the
/// view can paint them (gray) instead of leaving a misleading blank.
abstract final class MappingOverviewMath {
  /// [ms] as a 0..1 fraction of [fgTotalMs], clamped; null when the axis is
  /// unusable (no duration → the manager disables the feature instead).
  static double? fracOf(int ms, int fgTotalMs) {
    if (fgTotalMs <= 0) return null;
    return (ms / fgTotalMs).clamp(0.0, 1.0);
  }

  /// Ordered, non-overlapping blocks covering exactly `0..fgTotalMs`.
  ///
  /// Now activation-aware: only ACTIVE segments count and overlapping ones
  /// resolve by activation order, so the axis shows the mapping actually in
  /// effect (never a shadowed segment's full value). Delegates to
  /// [ActiveMappingResolver.visibleBlocks] — the single implementation shared
  /// with playback and the editor.
  static List<MappingBlock> layout({
    required List<MappingSegment> segments,
    required int fgTotalMs,
  }) =>
      ActiveMappingResolver.visibleBlocks(
        segments: segments,
        fgTotalMs: fgTotalMs,
      );
}

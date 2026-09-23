import 'package:iris/features/background_playback/model/domain/background_mapping.dart';

/// Position/binding decoupling helpers of the 副音 mapping manager.
///
/// The persisted [MappingSegment] couples three things in one row: the
/// foreground placement (A/B), the alignment (the implied offset
/// `bgStart - fgStart`, i.e. P), and the referenced background file. The
/// manager's "same span/position, swap the bg" operation must change ONLY the
/// file reference: the foreground placement and the offset stay byte-for-byte
/// identical, and the background window is recomputed from that offset — never
/// re-clamped to the new file's duration (an overflowing window is shown as a
/// gray uncovered region instead).
abstract final class MappingBinding {
  /// The constant offset `bgPos - fgPos` implied by a playMedia segment.
  /// Silence segments (no bg window) fall back to 0.
  static int offsetMsOf(MappingSegment segment) {
    final bs = segment.bgStartMs;
    if (bs == null) return 0;
    return bs - segment.fgStartMs;
  }

  /// Returns [segment] with its background binding replaced and its window
  /// re-derived from the unchanged offset, leaving A/B (and therefore P)
  /// untouched. Pass [bgTotalMs] when the new file's duration is known so the
  /// normalized mirror fields can be refreshed; otherwise they are cleared so
  /// no stale fraction of the OLD file is mistaken for a current one.
  static MappingSegment replaceBgKeepingSpan(
    MappingSegment segment, {
    required String bgStorageId,
    required String bgPath,
    int? bgTotalMs,
  }) {
    final off = offsetMsOf(segment);
    final bgStart = segment.fgStartMs + off;
    final bgEnd = segment.fgEndMs + off;
    final bool haveTotal = bgTotalMs != null && bgTotalMs > 0;
    return segment.copyWith(
      bgStorageId: bgStorageId,
      bgPath: bgPath,
      bgStartMs: bgStart,
      bgEndMs: bgEnd,
      bgStartN: haveTotal ? bgStart / bgTotalMs : null,
      bgEndN: haveTotal ? bgEnd / bgTotalMs : null,
    );
  }
}

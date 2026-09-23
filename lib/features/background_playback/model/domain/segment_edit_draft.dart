import 'package:iris/features/background_playback/model/domain/background_mapping.dart';
import 'package:iris/features/background_playback/model/enum/mapping_action.dart';
import 'package:iris/features/background_playback/resolver/mapping_timeline_math.dart';
import 'package:iris/features/background_playback/resolver/segment_span_math.dart';

/// Default per-segment volume split (sub_media §5.5): foreground 30%, 副音
/// 100%. Only affects the edited span; the media/global pair still applies
/// wherever a segment carries no explicit ratio.
const int kDefaultSegmentFgPercent = 30;
const int kDefaultSegmentBgPercent = 100;

/// In-progress A-center-B span of the segment editor.
///
/// Session-only: never persisted — the draft dies with the player session and
/// the editor is the only writer. [editingId] is the DB row being re-edited
/// (`0` = a brand new segment); the overlap solver uses it to exclude that row
/// from itself, and [toSegment] tags the result so a future save can keep the
/// identity if the repository ever switches to incremental writes.
class SegmentEditDraft {
  const SegmentEditDraft({
    required this.action,
    required this.span,
    this.editingId = 0,
    this.bgStorageId,
    this.bgPath,
    this.fgPercent = kDefaultSegmentFgPercent,
    this.bgPercent = kDefaultSegmentBgPercent,
    this.colorArgb,
    this.activeSeq = 0,
  });

  final MappingAction action;

  /// The 1:1 span on the foreground axis (A, B, bg offset).
  final SegmentSpan span;

  final int editingId;
  final String? bgStorageId;
  final String? bgPath;

  /// Per-segment volume split (0-100). `bgPercent == 0` keeps the file but
  /// silences 副音 for the span.
  final int fgPercent;
  final int bgPercent;

  /// Label colour on the foreground axis (ARGB). Null until the draft is given
  /// one (a re-edit keeps the stored colour; a new segment gets a random
  /// palette colour at seed time). Cosmetic only.
  final int? colorArgb;

  /// Activation order of the row under edit (0 for a brand-new segment). An
  /// overwrite keeps it so the re-edited mapping holds its lit position; a
  /// save-as-new ignores it and takes [ActiveMappingResolver.nextActiveSeq].
  final int activeSeq;

  bool get isPlayMedia => action == MappingAction.playMedia;

  /// True when the editor was opened ON an in-use saved segment, so Save must
  /// ask overwrite-vs-new. A new draft (id 0) is saved without a question.
  bool get hasOrigin => editingId != 0;

  /// Seeds a draft from a persisted segment (re-edit in place). The offset is
  /// reconstructed from the stored pair: `off = bgStart - fgStart`.
  factory SegmentEditDraft.fromSegment(MappingSegment s) => SegmentEditDraft(
        action: s.action,
        editingId: s.id,
        span: SegmentSpan(
          fgStartMs: s.fgStartMs,
          fgEndMs: s.fgEndMs,
          bgOffsetMs: (s.bgStartMs ?? 0) - s.fgStartMs,
        ),
        bgStorageId: s.bgStorageId,
        bgPath: s.bgPath,
        fgPercent: s.fgPercent ?? kDefaultSegmentFgPercent,
        bgPercent: s.bgPercent ?? kDefaultSegmentBgPercent,
        colorArgb: s.colorArgb,
        activeSeq: s.activeSeq,
      );

  /// Converts the draft into a persistable segment. A playMedia segment is
  /// written strictly 1:1 (`adjustedRate == 1.0`, equal window lengths); a
  /// silence segment carries no bg identity at all.
  MappingSegment toSegment({int? fgTotalMs, int? bgTotalMs}) {
    final s = span;
    return MappingSegment(
      id: editingId,
      action: action,
      fgStartMs: s.fgStartMs,
      fgEndMs: s.fgEndMs,
      fgStartN: MappingTimelineMath.normOf(s.fgStartMs, fgTotalMs),
      fgEndN: MappingTimelineMath.normOf(s.fgEndMs, fgTotalMs),
      bgStorageId: isPlayMedia ? bgStorageId : null,
      bgPath: isPlayMedia ? bgPath : null,
      bgStartMs: isPlayMedia ? s.bgStartMs : null,
      bgEndMs: isPlayMedia ? s.bgEndMs : null,
      bgStartN: isPlayMedia
          ? MappingTimelineMath.normOf(s.bgStartMs, bgTotalMs)
          : null,
      bgEndN: isPlayMedia
          ? MappingTimelineMath.normOf(s.bgEndMs, bgTotalMs)
          : null,
      adjustedRate: isPlayMedia ? 1.0 : null,
      // Silence segments carry no bg file and no ratio.
      fgPercent: isPlayMedia ? fgPercent : null,
      bgPercent: isPlayMedia ? bgPercent : null,
      colorArgb: colorArgb,
      activeSeq: activeSeq,
    );
  }

  /// Swaps the background binding, keeping A/B and the alignment (P) exactly:
  /// the bg window is re-derived from the unchanged offset when the draft is
  /// converted (see `MappingBinding.replaceBgKeepingSpan`), so an overflowing
  /// file shows as uncovered instead of re-clamping the span.
  SegmentEditDraft withBg({
    required String bgStorageId,
    required String bgPath,
  }) =>
      SegmentEditDraft(
        action: action,
        span: span,
        editingId: editingId,
        bgStorageId: bgStorageId,
        bgPath: bgPath,
        fgPercent: fgPercent,
        bgPercent: bgPercent,
        colorArgb: colorArgb,
        activeSeq: activeSeq,
      );

  SegmentEditDraft copyWith({
    MappingAction? action,
    SegmentSpan? span,
    int? editingId,
    String? bgStorageId,
    String? bgPath,
    int? fgPercent,
    int? bgPercent,
    int? colorArgb,
    int? activeSeq,
  }) =>
      SegmentEditDraft(
        action: action ?? this.action,
        span: span ?? this.span,
        editingId: editingId ?? this.editingId,
        bgStorageId: bgStorageId ?? this.bgStorageId,
        bgPath: bgPath ?? this.bgPath,
        fgPercent: fgPercent ?? this.fgPercent,
        bgPercent: bgPercent ?? this.bgPercent,
        colorArgb: colorArgb ?? this.colorArgb,
        activeSeq: activeSeq ?? this.activeSeq,
      );

  @override
  bool operator ==(Object other) =>
      other is SegmentEditDraft &&
      other.action == action &&
      other.span == span &&
      other.editingId == editingId &&
      other.bgStorageId == bgStorageId &&
      other.bgPath == bgPath &&
      other.fgPercent == fgPercent &&
      other.bgPercent == bgPercent &&
      other.colorArgb == colorArgb &&
      other.activeSeq == activeSeq;

  @override
  int get hashCode => Object.hash(
        action,
        span,
        editingId,
        bgStorageId,
        bgPath,
        fgPercent,
        bgPercent,
        colorArgb,
        activeSeq,
      );

  @override
  String toString() =>
      'SegmentEditDraft(${action.name}, $span, id=$editingId, '
      'bg=$bgStorageId/$bgPath, ratio=$fgPercent/$bgPercent, '
      'color=$colorArgb, seq=$activeSeq)';
}

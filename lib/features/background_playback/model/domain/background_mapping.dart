import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:iris/features/background_playback/model/enum/mapping_action.dart';

part 'background_mapping.freezed.dart';
part 'background_mapping.g.dart';

/// One mapped timeline segment (I/O point pair) on the foreground axis.
///
/// [fgStartMs..fgEndMs] is absolute foreground media time. For playMedia
/// segments [bgStorageId]/[bgPath] identify the real background file and
/// [bgStartMs..bgEndMs] its absolute window (normalized fractions mirrored in
/// the n-fields for display/drift checks).
@freezed
abstract class MappingSegment with _$MappingSegment {
  const factory MappingSegment({
    /// 0 = new (unsaved); otherwise the DB row id.
    @Default(0) int id,
    required MappingAction action,
    required int fgStartMs,
    required int fgEndMs,
    double? fgStartN,
    double? fgEndN,
    String? bgStorageId,
    String? bgPath,
    int? bgStartMs,
    int? bgEndMs,
    double? bgStartN,
    double? bgEndN,
    double? adjustedRate,
    /// Per-segment volume split (0-100). Null = fall back to the per-media /
    /// global pair. 0 bgPercent keeps the file but silences 副音 for the span.
    int? fgPercent,
    int? bgPercent,
    /// Label colour of this segment on the foreground axis, ARGB. Null = no
    /// explicit choice; the UI derives a stable colour. Cosmetic only.
    int? colorArgb,
    /// Whether the segment participates in playback/display (v34). A disabled
    /// segment keeps its data but is invisible to resolution.
    @Default(true) bool isActive,
    /// Per-foreground activation order (v34). Larger = later activation; the
    /// largest sequence wins wherever ACTIVE segments overlap. Never compared
    /// across foregrounds.
    @Default(0) int activeSeq,
  }) = _MappingSegment;

  factory MappingSegment.fromJson(Map<String, dynamic> json) =>
      _$MappingSegmentFromJson(json);
}

/// Single mapping timeline of one foreground media file (single set, v1).
@freezed
abstract class BackgroundMappingTimeline with _$BackgroundMappingTimeline {
  const factory BackgroundMappingTimeline({
    required String storageId,
    required String path,
    int? fgTotalMs,
    DateTime? updatedAt,
    @Default(<MappingSegment>[]) List<MappingSegment> segments,
  }) = _BackgroundMappingTimeline;

  factory BackgroundMappingTimeline.fromJson(Map<String, dynamic> json) =>
      _$BackgroundMappingTimelineFromJson(json);
}

extension MappingSegmentExt on MappingSegment {
  bool get isPlayMedia => action == MappingAction.playMedia;
}

extension BackgroundMappingTimelineExt on BackgroundMappingTimeline {
  /// Segments sorted by fgStart; callers normalize through the repository.
  List<MappingSegment> get sortedSegments {
    final list = List<MappingSegment>.of(segments)
      ..sort((a, b) => a.fgStartMs.compareTo(b.fgStartMs));
    return list;
  }
}

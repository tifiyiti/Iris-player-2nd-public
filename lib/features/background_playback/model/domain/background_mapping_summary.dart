import 'package:freezed_annotation/freezed_annotation.dart';

part 'background_mapping_summary.freezed.dart';
part 'background_mapping_summary.g.dart';

/// Level-1 row of the 副音 mapping manager: one foreground file that owns a
/// saved timeline.
///
/// Deliberately art-free (the manager is a two-level text/timeline UI, no
/// preview images). [fgTotalMs] is the foreground duration the timeline was
/// authored against; the repository fills it from the saved snapshot and, when
/// that is absent, from the scanned `media_nodes.durationMs`. A still-null
/// value means the feature is unavailable for this fg — the manager warns and
/// disables it rather than rendering an axis it cannot scale.
@freezed
abstract class BackgroundMappingSummary with _$BackgroundMappingSummary {
  const factory BackgroundMappingSummary({
    required String storageId,
    required String path,
    int? mediaId,
    int? fgTotalMs,
    DateTime? updatedAt,
    @Default(0) int segmentCount,
    @Default(<String>[]) List<String> bgNames,
    /// Display name of the foreground file when a scanned `media_nodes` row is
    /// known; null falls back to the path basename.
    String? fgName,
  }) = _BackgroundMappingSummary;

  factory BackgroundMappingSummary.fromJson(Map<String, dynamic> json) =>
      _$BackgroundMappingSummaryFromJson(json);
}

extension BackgroundMappingSummaryX on BackgroundMappingSummary {
  /// Whether a usable foreground duration exists; false disables the feature
  /// for this fg (per the manager's "no duration → warn, no function" rule).
  bool get hasFgDuration => (fgTotalMs ?? 0) > 0;

  /// Foreground identity key used to key staged edits: `storageId:path`.
  String get key => '$storageId:$path';

  /// Human title: the scanned name when known, else the path basename.
  String get displayName {
    final n = fgName;
    if (n != null && n.isNotEmpty) return n;
    final i = path.lastIndexOf('/');
    return i < 0 || i == path.length - 1 ? path : path.substring(i + 1);
  }
}

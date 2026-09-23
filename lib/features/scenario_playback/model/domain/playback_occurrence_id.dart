import 'package:freezed_annotation/freezed_annotation.dart';

part 'playback_occurrence_id.freezed.dart';
part 'playback_occurrence_id.g.dart';

/// The stable identity of one playable occurrence (A3/C7/D4).
///
/// Resolver identity is NOT `mediaId` and NOT a raw path string — it is this
/// composite: `(mediaRef, occurrenceIndex)` with an optional future
/// `sourceInstanceId`. The resolver must never `GROUP BY mediaId`, otherwise
/// duplicated media (same file from two sources under `allowDuplicate`) would be
/// wrongly collapsed.
@freezed
abstract class PlaybackOccurrenceId with _$PlaybackOccurrenceId {
  const PlaybackOccurrenceId._();

  const factory PlaybackOccurrenceId({
    required String storageId,
    required String path,
    /// 0-based occurrence within duplicated media (A3).
    @Default(0) int occurrenceIndex,
    /// Reserved for future source-instance disambiguation (C7). Unused in v1.
    String? sourceInstanceId,
  }) = _PlaybackOccurrenceId;

  factory PlaybackOccurrenceId.fromJson(Map<String, dynamic> json) =>
      _$PlaybackOccurrenceIdFromJson(json);

  /// Stable string key (storageId:path), used for dedup and equality.
  String get mediaKey => '$storageId:$path';

  /// Full occurrence key including the occurrence index.
  String get occurrenceKey => '$mediaKey#$occurrenceIndex';
}

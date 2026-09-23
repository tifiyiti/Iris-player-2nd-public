import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:iris/features/scenario_playback/model/enum/scenario_source_kind.dart';

part 'origin_reference.freezed.dart';

/// Which ScenarioSource produced an [EffectivePlaybackItem].
///
/// Kept in the runtime model (not via SQL aggregation) so the UI can show
/// "from Anime source" style metadata (A2/C8).
@freezed
abstract class OriginReference with _$OriginReference {
  const factory OriginReference({
    required int sourceId,
    required ScenarioSourceKind sourceKind,
  }) = _OriginReference;
}

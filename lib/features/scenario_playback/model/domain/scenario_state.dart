import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:iris/features/scenario_playback/model/domain/playback_occurrence_id.dart';

part 'scenario_state.freezed.dart';
part 'scenario_state.g.dart';

/// JSON converter so json_serializable can round-trip [PlaybackOccurrenceId]
/// (it already has generated fromJson/toJson).
class PlaybackOccurrenceIdConverter
    implements JsonConverter<PlaybackOccurrenceId?, Map<String, dynamic>?> {
  const PlaybackOccurrenceIdConverter();

  @override
  PlaybackOccurrenceId? fromJson(Map<String, dynamic>? json) =>
      json == null ? null : PlaybackOccurrenceId.fromJson(json);

  @override
  Map<String, dynamic>? toJson(PlaybackOccurrenceId? value) => value?.toJson();
}

/// PLAYBACK STATE of a [Scenario] (D1/D4) — the runtime half, persisted with
/// the scenario so "play again later" resumes exactly where it left off.
///
/// Definition config (sorting, shuffle configuration, duplicate policy, repeat
/// mode) lives on [Scenario], NOT here.
///
/// IMPORTANT: never depend on a stored array index. The current item is
/// identified by [currentPlaybackOccurrence] (a JSON
/// [PlaybackOccurrenceId]) plus a [currentVirtualPos] hint for O(1) next/prev.
@freezed
abstract class ScenarioState with _$ScenarioState {
  const factory ScenarioState({
    required String scenarioId,
    /// JSON of [PlaybackOccurrenceId] (D4). Opaque to SQL.
    @PlaybackOccurrenceIdConverter() PlaybackOccurrenceId? currentPlaybackOccurrence,
    /// Ordering hint of the current item in the current resolve order.
    int? currentVirtualPos,
    /// Deterministic shuffle seed. Never store the whole shuffled array.
    int? shuffleSeed,
    /// Incremented each time the shuffle order is regenerated.
    @Default(0) int shuffleVersion,
    /// Item count at the time the shuffle was generated.
    @Default(0) int shuffleItemCount,
    /// Which userSaved Scenario this playing workspace was last overridden from
    /// (E2/F2). Null ⇒ Sync-back disabled. Kept on Append; replaced on Override.
    String? originScenarioId,
    DateTime? importedAt,
    int? importVersion,
    DateTime? lastActiveAt,
  }) = _ScenarioState;

  factory ScenarioState.fromJson(Map<String, dynamic> json) =>
      _$ScenarioStateFromJson(json);
}

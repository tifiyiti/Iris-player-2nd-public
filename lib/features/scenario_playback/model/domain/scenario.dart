import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:iris/features/media_library/model/enum/basic_enum.dart';
import 'package:iris/features/scenario_playback/model/enum/duplicate_policy.dart';
import 'package:iris/features/scenario_playback/model/enum/playback_order.dart';
import 'package:iris/features/scenario_playback/model/enum/scenario_kind.dart';
import 'package:iris/features/scenario_playback/model/enum/scenario_sort_field.dart';
import 'package:iris/models/store/app_state.dart' show Repeat;

part 'scenario.freezed.dart';
part 'scenario.g.dart';

/// An independent playback environment — either the single SystemPlaying
/// workspace or a user-saved plan (C2/A1).
///
/// There is exactly ONE domain class. The SystemPlayingScenario is simply a
/// [Scenario] whose [type] is [ScenarioKind.systemPlaying]. Repos/stores/
/// providers operate on that row; there is no parallel class.
///
/// A [Scenario] stores only DEFINITION (D1): where media comes from (sources),
/// explicit items, exclusions, sorting, shuffle configuration, duplicate policy
/// and repeat mode. Runtime playback state lives in [ScenarioState].
@freezed
abstract class Scenario with _$Scenario {
  const factory Scenario({
    required String id,
    required String name,
    String? description,
    @Default(ScenarioKind.userSaved) ScenarioKind type,

    /// Null for systemPlaying, >= 0 for userSaved (E4).
    int? version,
    // ── Definition config (D1) ──
    @JsonKey(unknownEnumValue: ScenarioSortField.name)
    @Default(ScenarioSortField.name)
    ScenarioSortField sortField,
    @Default(SortDirection.asc) SortDirection sortDirection,

    /// The queue-generation rule captured when the scenario was first
    /// populated (the sort the user saw in the source view). Null for
    /// materialized (explicit) queues, whose "Original" order is the
    /// as-added addOrder. "Original" in the order menu restores this.
    @JsonKey(unknownEnumValue: ScenarioSortField.name)
    ScenarioSortField? originalSortField,

    /// Shuffle configuration (preference). The actual seed is Playback State.
    @Default(PlaybackOrder.sequential) PlaybackOrder order,
    @Default(DuplicatePolicy.allowDuplicate) DuplicatePolicy duplicatePolicy,
    @Default(Repeat.none) Repeat repeatMode,

    /// When true the queue always groups by source (source-internal sort first)
    /// and orders each source by (parentPath, sortField, name) so files of the
    /// same directory stay contiguous. When false each source is sorted by
    /// sortField only. Defaults to true (D5/D6).
    @Default(true) bool sourceInternalFirst,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) = _Scenario;

  factory Scenario.fromJson(Map<String, dynamic> json) =>
      _$ScenarioFromJson(json);
}

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:iris/features/scenario_playback/model/enum/scenario_source_kind.dart';

part 'scenario_source.freezed.dart';
part 'scenario_source.g.dart';

/// A bulk media producer owned by exactly one [Scenario] (C4).
///
/// It is intentionally NOT a global [MediaSource] object and NOT an explicit
/// item: it produces media in bulk from (storageId, path). Explicit picks are
/// modeled separately in [ScenarioExplicitItem].
@freezed
abstract class ScenarioSource with _$ScenarioSource {
  const factory ScenarioSource({
    required int id,
    required String scenarioId,
    required String storageId,
    /// Path relative to the storage root. Empty string = entire storage.
    required String path,
    @Default(false) bool recursive,
    @Default(ScenarioSourceKind.folder) ScenarioSourceKind sourceKind,
    /// Insertion timeline within the scenario (A4): max+1, never reused.
    @Default(0) int sortOrder,
    DateTime? createdAt,
  }) = _ScenarioSource;

  factory ScenarioSource.fromJson(Map<String, dynamic> json) =>
      _$ScenarioSourceFromJson(json);
}

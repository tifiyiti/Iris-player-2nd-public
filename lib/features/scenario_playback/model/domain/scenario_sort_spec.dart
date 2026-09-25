import 'package:iris/features/media_library/model/enum/basic_enum.dart';
import 'package:iris/features/scenario_playback/model/domain/scenario.dart';
import 'package:iris/features/scenario_playback/model/enum/duplicate_policy.dart';
import 'package:iris/features/scenario_playback/model/enum/playback_order.dart';
import 'package:iris/features/scenario_playback/model/enum/scenario_sort_field.dart';

/// Immutable value object capturing a scenario's resolution sort view.
///
/// Mirrors the Definition knobs the resolver understands ([Scenario]'s
/// sortField / sortDirection / order / duplicatePolicy / sourceInternalFirst
/// plus the shuffle seed from [ScenarioState]) so a read-only view (e.g. the
/// Preview page) can re-resolve temporarily and — on an explicit user action —
/// be applied back to a workspace via dirty-check.
class ScenarioSortSpec {
  final ScenarioSortField sortField;
  final SortDirection sortDirection;
  final PlaybackOrder order;
  final int? shuffleSeed;
  final DuplicatePolicy duplicatePolicy;
  final bool sourceInternalFirst;

  const ScenarioSortSpec({
    required this.sortField,
    required this.sortDirection,
    this.order = PlaybackOrder.sequential,
    this.shuffleSeed,
    this.duplicatePolicy = DuplicatePolicy.allowDuplicate,
    this.sourceInternalFirst = false,
  });

  /// True when shuffled with a usable seed (resolution needs both).
  bool get shuffled => order == PlaybackOrder.shuffled && shuffleSeed != null;

  /// Builds the spec the resolver would use from [scenario]'s Definition plus
  /// [seed] (the persisted [ScenarioState.shuffleSeed]). The seed is only
  /// meaningful when the scenario order is shuffled, so it is normalized to
  /// null otherwise — this keeps the dirty-check symmetric with the Preview
  /// seeding (a sequential order never carries a seed).
  static ScenarioSortSpec fromScenario(Scenario scenario, int? seed) =>
      ScenarioSortSpec(
        sortField: scenario.sortField,
        sortDirection: scenario.sortDirection,
        order: scenario.order,
        shuffleSeed: scenario.order == PlaybackOrder.shuffled ? seed : null,
        duplicatePolicy: scenario.duplicatePolicy,
        sourceInternalFirst: scenario.sourceInternalFirst,
      );

  /// [shuffleSeed] uses a provider so an explicit `() => null` clears the seed
  /// (distinct from omitting the argument, which keeps the current seed).
  ScenarioSortSpec copyWith({
    ScenarioSortField? sortField,
    SortDirection? sortDirection,
    PlaybackOrder? order,
    int? Function()? shuffleSeed,
    DuplicatePolicy? duplicatePolicy,
    bool? sourceInternalFirst,
  }) {
    return ScenarioSortSpec(
      sortField: sortField ?? this.sortField,
      sortDirection: sortDirection ?? this.sortDirection,
      order: order ?? this.order,
      shuffleSeed: shuffleSeed != null ? shuffleSeed() : this.shuffleSeed,
      duplicatePolicy: duplicatePolicy ?? this.duplicatePolicy,
      sourceInternalFirst: sourceInternalFirst ?? this.sourceInternalFirst,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ScenarioSortSpec &&
        other.sortField == sortField &&
        other.sortDirection == sortDirection &&
        other.order == order &&
        other.shuffleSeed == shuffleSeed &&
        other.duplicatePolicy == duplicatePolicy &&
        other.sourceInternalFirst == sourceInternalFirst;
  }

  @override
  int get hashCode => Object.hash(
        sortField,
        sortDirection,
        order,
        shuffleSeed,
        duplicatePolicy,
        sourceInternalFirst,
      );

  @override
  String toString() =>
      'ScenarioSortSpec(sortField: $sortField, sortDirection: $sortDirection, '
      'order: $order, shuffleSeed: $shuffleSeed, duplicatePolicy: '
      '$duplicatePolicy, sourceInternalFirst: $sourceInternalFirst)';
}

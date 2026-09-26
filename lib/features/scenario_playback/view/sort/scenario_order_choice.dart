import 'package:iris/features/scenario_playback/model/enum/playback_order.dart';
import 'package:iris/features/scenario_playback/model/enum/scenario_sort_field.dart';

/// One row of a scenario order menu (the popup's value type).
///
/// The order doubles as the render order: `shuffled`, `original`, then the four
/// concrete sort fields, matching every order menu in the feature.
enum ScenarioOrderChoice {
  shuffled,
  original,
  name,
  modifiedAt,
  durationMs,
  sizeInBytes,
}

extension ScenarioOrderChoiceField on ScenarioOrderChoice {
  /// The sort field a concrete row selects.
  ///
  /// `shuffled` and `original` carry none: shuffling is an order, and
  /// [ScenarioOrderChoice.original] is an ACTION that restores the captured
  /// queue-generation rule (`Scenario.originalSortField`) — the rule is always
  /// just another (field, direction) pair, so it has no field of its own.
  ScenarioSortField? get sortField {
    switch (this) {
      case ScenarioOrderChoice.name:
        return ScenarioSortField.name;
      case ScenarioOrderChoice.modifiedAt:
        return ScenarioSortField.modifiedAt;
      case ScenarioOrderChoice.durationMs:
        return ScenarioSortField.durationMs;
      case ScenarioOrderChoice.sizeInBytes:
        return ScenarioSortField.sizeInBytes;
      case ScenarioOrderChoice.shuffled:
      case ScenarioOrderChoice.original:
        return null;
    }
  }
}

/// The ONE order-menu row to mark as active.
///
/// Shuffled wins when the scenario is shuffled; otherwise the CONCRETE sort
/// field wins, always.
///
/// [ScenarioOrderChoice.original] is deliberately never returned: the captured
/// generation rule is not a separate state, it is a (field, direction) pair. It
/// used to be aliased onto its matching field and take priority, so a queue
/// captured from a page sorted by NAME could never show "Name" as active —
/// clicking Name only flipped the arrow while the menu kept pointing at
/// Original, which reads as a dead click. Callers keep the row as an action and
/// name the field it restores in its label.
ScenarioOrderChoice resolveScenarioOrderChoice({
  required PlaybackOrder order,
  required ScenarioSortField sortField,
}) {
  if (order == PlaybackOrder.shuffled) return ScenarioOrderChoice.shuffled;
  switch (sortField) {
    case ScenarioSortField.name:
      return ScenarioOrderChoice.name;
    case ScenarioSortField.modifiedAt:
      return ScenarioOrderChoice.modifiedAt;
    case ScenarioSortField.durationMs:
      return ScenarioOrderChoice.durationMs;
    case ScenarioSortField.sizeInBytes:
      return ScenarioOrderChoice.sizeInBytes;
  }
}

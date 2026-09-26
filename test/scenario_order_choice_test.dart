import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/scenario_playback/model/enum/playback_order.dart';
import 'package:iris/features/scenario_playback/model/enum/scenario_sort_field.dart';
import 'package:iris/features/scenario_playback/view/sort/scenario_order_choice.dart';

/// The order menu marks exactly ONE row as active, and that row must be the
/// user's last explicit choice.
///
/// Regression: "Original" used to alias whichever field equalled
/// `Scenario.originalSortField` and won over the concrete field, so a queue
/// captured from a browse page sorted by NAME (the common shape of every
/// override-populated queue) never showed "Name" as active — clicking Name only
/// flipped the arrow while the menu kept pointing at Original, which reads as a
/// dead click. The captured rule no longer takes part in the choice at all; it
/// is only a label ("Original (Name)").
void main() {
  ScenarioOrderChoice resolve({
    PlaybackOrder order = PlaybackOrder.sequential,
    ScenarioSortField sortField = ScenarioSortField.name,
  }) =>
      resolveScenarioOrderChoice(order: order, sortField: sortField);

  group('the concrete field wins', () {
    for (final field in ScenarioSortField.values) {
      test('$field highlights its own row', () {
        expect(
          resolve(sortField: field),
          ScenarioOrderChoice.values.byName(field.name),
        );
      });
    }
  });

  group('shuffled wins', () {
    test('over any concrete field', () {
      expect(
        resolve(order: PlaybackOrder.shuffled),
        ScenarioOrderChoice.shuffled,
      );
      expect(
        resolve(
          order: PlaybackOrder.shuffled,
          sortField: ScenarioSortField.durationMs,
        ),
        ScenarioOrderChoice.shuffled,
      );
    });
  });

  group('original is an action, not a state', () {
    test('no (order, field) pair ever resolves to it', () {
      for (final field in ScenarioSortField.values) {
        for (final order in PlaybackOrder.values) {
          expect(
            resolve(order: order, sortField: field),
            isNot(ScenarioOrderChoice.original),
          );
        }
      }
    });

    test('it carries no field: it restores the captured rule instead', () {
      expect(ScenarioOrderChoice.original.sortField, isNull);
      expect(ScenarioOrderChoice.shuffled.sortField, isNull);
    });

    test('every concrete row maps to its field', () {
      expect(ScenarioOrderChoice.name.sortField, ScenarioSortField.name);
      expect(ScenarioOrderChoice.modifiedAt.sortField,
          ScenarioSortField.modifiedAt);
      expect(ScenarioOrderChoice.durationMs.sortField,
          ScenarioSortField.durationMs);
      expect(ScenarioOrderChoice.sizeInBytes.sortField,
          ScenarioSortField.sizeInBytes);
    });
  });

  test('the enum order is the row order the popup renders in', () {
    expect(ScenarioOrderChoice.values, const [
      ScenarioOrderChoice.shuffled,
      ScenarioOrderChoice.original,
      ScenarioOrderChoice.name,
      ScenarioOrderChoice.modifiedAt,
      ScenarioOrderChoice.durationMs,
      ScenarioOrderChoice.sizeInBytes,
    ]);
  });
}

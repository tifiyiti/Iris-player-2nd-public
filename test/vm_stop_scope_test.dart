import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/virtual_media/playback/vm_playback_controller.dart';

/// `stop`/`stopToFirst` must clear ONLY the current (scenario, tag, scope)
/// progress row — never every scenario's row for the scope.
void main() {
  group('resolveVmProgressScope', () {
    test('null scenario resolves to null (caller must skip, never nuke)',
        () {
      expect(
        resolveVmProgressScope(
            activeScenarioId: null, activeViewTagId: null),
        isNull,
      );
    });

    test('empty scenario resolves to null', () {
      expect(
        resolveVmProgressScope(activeScenarioId: '', activeViewTagId: null),
        isNull,
      );
    });

    test('scenario without tag view uses empty tagId', () {
      expect(
        resolveVmProgressScope(
            activeScenarioId: 'sys-playing', activeViewTagId: null),
        (scenarioId: 'sys-playing', tagId: ''),
      );
    });

    test('scenario with tag view carries the tag id as string', () {
      expect(
        resolveVmProgressScope(
            activeScenarioId: 'user-1', activeViewTagId: 3),
        (scenarioId: 'user-1', tagId: '3'),
      );
    });
  });
}

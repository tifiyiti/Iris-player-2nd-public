import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/scenario_playback/view/queue/paged_scenario_media_data_source.dart';

void main() {
  // Regression: "Open in folder" from the docked scenario queue used to call
  // `replacePopup` unconditionally. The docked panel is NOT a route (it is
  // embedded in Home), so `pushReplacement` replaced the ROOT route -> white
  // screen, player unmounted (see ScenarioBrowserStore doc). The docked host
  // must PUSH a floating StoragesDb popup instead.
  group('resolveOpenInFolderHost', () {
    test('docked panel pushes a popup (never replaces the root route)', () {
      expect(
        resolveOpenInFolderHost(dockedPanel: true),
        OpenInFolderHost.pushPopup,
      );
    });

    test('floating queue popup replaces its own route', () {
      expect(
        resolveOpenInFolderHost(dockedPanel: false),
        OpenInFolderHost.replaceCurrentRoute,
      );
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/models/store/phone_landscape_slider_type_helper.dart';

/// Desktop hover policy gate.
///
/// `shouldRequireClickToShowPanel` / `desktopHoverRevealsTitle` are the single
/// authorities every passive-hover path consults. The two `desktopHoverShow*`
/// switches only gate hover; explicit shows ignore them. Adding the desktop
/// bits must not disturb the legacy one-handed side-panel rule, and they must
/// stay inert while the metadata gate is OFF so legacy-blob installs keep
/// today's hover-reveals-everything behavior.
void main() {
  group('desktop hover policy', () {
    test('default: title ON, control bar OFF → hover needs a click for the bar',
        () {
      const state = AppState(useMetadataSettings: true);
      expect(state.desktopHoverShowTitle, isTrue);
      expect(state.desktopHoverShowControlBar, isFalse);
      expect(shouldRequireClickToShowPanel(state), isTrue);
      expect(desktopHoverRevealsTitle(state), isTrue);
    });

    test('control bar ON → hover reveals the full bar (no click needed)', () {
      const state = AppState(
        useMetadataSettings: true,
        desktopHoverShowControlBar: true,
      );
      expect(shouldRequireClickToShowPanel(state), isFalse);
      expect(desktopHoverRevealsTitle(state), isTrue);
    });

    test('title OFF alone → hover still needs a click and reveals no title',
        () {
      const state = AppState(
        useMetadataSettings: true,
        desktopHoverShowTitle: false,
      );
      expect(shouldRequireClickToShowPanel(state), isTrue);
      expect(desktopHoverRevealsTitle(state), isFalse);
    });

    test('both OFF → hover reveals neither title nor bar', () {
      const state = AppState(
        useMetadataSettings: true,
        desktopHoverShowTitle: false,
        desktopHoverShowControlBar: false,
      );
      expect(shouldRequireClickToShowPanel(state), isTrue);
      expect(desktopHoverRevealsTitle(state), isFalse);
    });

    test('metadata gate OFF degrades both bits to legacy behavior', () {
      const state = AppState(
        useMetadataSettings: false,
        desktopHoverShowTitle: false,
        desktopHoverShowControlBar: false,
      );
      expect(shouldRequireClickToShowPanel(state), isFalse);
      expect(desktopHoverRevealsTitle(state), isTrue);
    });

    test('one-handed side-panel rule is unchanged', () {
      const state = AppState(
        useMetadataSettings: true,
        sidewayPanelRequireClick: true,
        phoneLandscapeUseMode: PhoneLandscapeUseMode.rightSide,
      );
      expect(shouldRequireClickToShowPanel(state), isTrue);
    });

    test('on desktop the hover policy owns the gate (one-handed flag ignored)',
        () {
      // Desktop no longer falls through to the one-handed side-panel rule: the
      // control-bar toggle alone decides, so a non-one-handed mode still gates
      // while the bar switch is OFF (the pre-meta default hover-reveals-all is
      // intentionally superseded).
      const state = AppState(
        useMetadataSettings: true,
        sidewayPanelRequireClick: true,
        phoneLandscapeUseMode: PhoneLandscapeUseMode.normal,
      );
      expect(shouldRequireClickToShowPanel(state), isTrue);
    });
  });
}

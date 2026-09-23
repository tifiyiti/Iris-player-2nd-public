import 'package:flutter_test/flutter_test.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/models/store/phone_landscape_slider_type_helper.dart';
import 'package:iris/models/store/player_ui_state.dart';
import 'package:iris/models/store/scrub_drag_state.dart';

void main() {
  group('mayHideControl', () {
    bool mayHide(PlayerUiState ui, ScrubDragState drag) =>
        mayHideControl(ui: ui, drag: drag);

    test('plain visible state is hideable', () {
      expect(
        mayHide(const PlayerUiState(), const ScrubDragState()),
        isTrue,
      );
    });

    test('already hidden state never hides again', () {
      expect(
        mayHide(const PlayerUiState(isShowControl: false), const ScrubDragState()),
        isFalse,
      );
    });

    test('desktop hover keeps controls alive', () {
      expect(
        mayHide(const PlayerUiState(isHovering: true), const ScrubDragState()),
        isFalse,
      );
    });

    test('active seek session keeps controls alive (hold-still mid-drag)', () {
      expect(
        mayHide(
          const PlayerUiState(),
          const ScrubDragState(seekOwners: <String>{'x'}),
        ),
        isFalse,
      );
    });

    test('active hold session keeps controls alive', () {
      expect(
        mayHide(
          const PlayerUiState(),
          const ScrubDragState(holdOwners: <String>{'x'}),
        ),
        isFalse,
      );
    });

    test('a seek session also counts as holding (completion suppression)', () {
      const drag = ScrubDragState(seekOwners: <String>{'x'});
      expect(drag.isScrubbing, isTrue);
      expect(drag.isHolding, isTrue);
      expect(drag.any, isTrue);
    });

    test('a hold-only session is NOT a scrub (副音 mirror must not stand down)', () {
      const drag = ScrubDragState(holdOwners: <String>{'x'});
      expect(drag.isScrubbing, isFalse);
      expect(drag.isHolding, isTrue);
      expect(drag.any, isTrue);
    });
  });

  group('resolveControlPanelVisible', () {
    bool visible({
      AppState appState = const AppState(),
      bool isShowControl = true,
      bool isHoverReveal = false,
      bool isPanelClickArmed = false,
      bool editing = false,
      bool isVideo = true,
      bool dragActive = false,
    }) =>
        resolveControlPanelVisible(
          appState: appState,
          isShowControl: isShowControl,
          isHoverReveal: isHoverReveal,
          isPanelClickArmed: isPanelClickArmed,
          editing: editing,
          isVideo: isVideo,
          dragActive: dragActive,
        );

    test('a video follows isShowControl', () {
      expect(visible(), isTrue);
      expect(visible(isShowControl: false), isFalse);
    });

    test('a non-video file pins the bar up', () {
      expect(visible(isShowControl: false, isVideo: false), isTrue);
    });

    test('a scrub session pins the bar up', () {
      expect(visible(isShowControl: false, dragActive: true), isTrue);
    });

    test('the align editor pins the bar up', () {
      expect(visible(isShowControl: false, editing: true), isTrue);
    });

    test('require-click hides a passive hover until the panel is armed', () {
      // Desktop: requireClick == metadata gate ON && !desktopHoverShowControlBar.
      const AppState requireClickOn =
          AppState(useMetadataSettings: true, desktopHoverShowControlBar: false);

      expect(
        visible(
          appState: requireClickOn,
          isHoverReveal: true,
          isPanelClickArmed: false,
        ),
        isFalse,
      );
      expect(
        visible(
          appState: requireClickOn,
          isHoverReveal: true,
          isPanelClickArmed: true,
        ),
        isTrue,
      );
      // An explicit show never obeys the hover switches.
      expect(
        visible(
          appState: requireClickOn,
          isHoverReveal: false,
          isPanelClickArmed: false,
        ),
        isTrue,
      );
    });
  });
}

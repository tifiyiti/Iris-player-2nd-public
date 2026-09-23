import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/models/store/phone_landscape_slider_type_helper.dart';
import 'package:iris/utils/platform.dart' show debugIsMobilePlatformOverride;

AppState _state({
  required bool gate,
  PhoneLandscapeUseMode mode = PhoneLandscapeUseMode.rightSide,
  PhoneSidePositionH h = PhoneSidePositionH.right,
  PhoneSidePositionV v = PhoneSidePositionV.bottom,
  PhoneSidePositionH mobileH = PhoneSidePositionH.right,
  PhoneLandscapeSliderType sliderType = PhoneLandscapeSliderType.circleRight,
}) =>
    AppState(
      useMetadataSettings: gate,
      phoneLandscapeUseMode: mode,
      phoneSidePositionH: h,
      phoneSidePositionV: v,
      mobileSidePositionH: mobileH,
      phoneLandscapeSliderType: sliderType,
    );

void main() {
  group('resolveSidePanelAlignment — meta gate ON (9-grid anchors)', () {
    test('horizontal × vertical combos map to the matching Alignment', () {
      final cases = <(PhoneSidePositionH, PhoneSidePositionV, Alignment)>[
        (PhoneSidePositionH.left, PhoneSidePositionV.top, Alignment.topLeft),
        (
          PhoneSidePositionH.center,
          PhoneSidePositionV.top,
          Alignment.topCenter
        ),
        (
          PhoneSidePositionH.right,
          PhoneSidePositionV.top,
          Alignment.topRight
        ),
        (
          PhoneSidePositionH.left,
          PhoneSidePositionV.middle,
          Alignment.centerLeft
        ),
        (PhoneSidePositionH.center, PhoneSidePositionV.middle, Alignment.center),
        (
          PhoneSidePositionH.right,
          PhoneSidePositionV.middle,
          Alignment.centerRight
        ),
        (
          PhoneSidePositionH.left,
          PhoneSidePositionV.bottom,
          Alignment.bottomLeft
        ),
        (
          PhoneSidePositionH.center,
          PhoneSidePositionV.bottom,
          Alignment.bottomCenter
        ),
        (
          PhoneSidePositionH.right,
          PhoneSidePositionV.bottom,
          Alignment.bottomRight
        ),
      ];
      for (final (h, v, expected) in cases) {
        expect(
          resolveSidePanelAlignment(_state(gate: true, h: h, v: v)),
          expected,
          reason: '$h × $v should anchor at $expected',
        );
      }
    });
  });

  group('resolveSidePanelAlignment — degradation', () {
    test('gate OFF falls back to the mode-derived corner', () {
      expect(
        resolveSidePanelAlignment(_state(
          gate: false,
          mode: PhoneLandscapeUseMode.leftSide,
          h: PhoneSidePositionH.right,
          v: PhoneSidePositionV.top,
        )),
        Alignment.bottomLeft,
      );
      expect(
        resolveSidePanelAlignment(_state(
          gate: false,
          mode: PhoneLandscapeUseMode.rightSide,
        )),
        Alignment.bottomRight,
      );
    });

    test('normal mode always anchors bottom-center', () {
      expect(
        resolveSidePanelAlignment(_state(
          gate: true,
          mode: PhoneLandscapeUseMode.normal,
          h: PhoneSidePositionH.left,
          v: PhoneSidePositionV.top,
        )),
        Alignment.bottomCenter,
      );
    });
  });

  group('resolveControlPanelAnchor — where the panel box ACTUALLY lands', () {
    test('one-handed Windows desk keeps the 9-grid anchor', () {
      // Branch 1 is Windows-gated by design, so this case is host-bound.
      if (!isWindows) return;
      expect(
        resolveControlPanelAnchor(
          _state(gate: true, h: PhoneSidePositionH.left),
          isLandscape: false,
          width: 1920,
        ),
        Alignment.bottomLeft,
      );
    });

    test('one-handed phone landscape follows the phone anchor', () {
      debugIsMobilePlatformOverride = true;
      addTearDown(() => debugIsMobilePlatformOverride = null);

      expect(
        resolveControlPanelAnchor(
          _state(gate: true, mobileH: PhoneSidePositionH.left),
          isLandscape: true,
          width: 800,
        ),
        Alignment.bottomLeft,
      );
      expect(
        resolveControlPanelAnchor(
          _state(gate: true, mobileH: PhoneSidePositionH.right),
          isLandscape: true,
          width: 800,
        ),
        Alignment.bottomRight,
      );
    });

    test('one-handed mode wins over the plain circle corner', () {
      debugIsMobilePlatformOverride = true;
      addTearDown(() => debugIsMobilePlatformOverride = null);

      // One-handed (anchor right) + a circle-LEFT slider type: the panel follows
      // the one-handed anchor, NOT the circle's own bottom-left corner.
      expect(
        resolveControlPanelAnchor(
          _state(
            gate: true,
            mode: PhoneLandscapeUseMode.rightSide,
            sliderType: PhoneLandscapeSliderType.circleLeft,
          ),
          isLandscape: true,
          width: 800,
        ),
        Alignment.bottomRight,
      );
    });

    test('the plain circle-left/right slider docks at its own corner', () {
      debugIsMobilePlatformOverride = true;
      addTearDown(() => debugIsMobilePlatformOverride = null);

      Alignment dockedAt(PhoneLandscapeSliderType type) =>
          resolveControlPanelAnchor(
            _state(
              gate: true,
              mode: PhoneLandscapeUseMode.normal,
              sliderType: type,
            ),
            isLandscape: true,
            width: 800,
          );

      expect(dockedAt(PhoneLandscapeSliderType.circleLeft),
          Alignment.bottomLeft);
      expect(dockedAt(PhoneLandscapeSliderType.circleRight),
          Alignment.bottomRight);
    });

    test('the circle corner only applies inside the mobile/tablet band', () {
      debugIsMobilePlatformOverride = true;
      addTearDown(() => debugIsMobilePlatformOverride = null);

      final AppState state = _state(
        gate: true,
        mode: PhoneLandscapeUseMode.normal,
        sliderType: PhoneLandscapeSliderType.circleLeft,
      );

      expect(resolveControlPanelAnchor(state, isLandscape: true, width: 639),
          Alignment.bottomCenter);
      expect(resolveControlPanelAnchor(state, isLandscape: true, width: 1024),
          Alignment.bottomCenter);
    });

    test('normal mode and a normal slider stay bottom-centre', () {
      debugIsMobilePlatformOverride = true;
      addTearDown(() => debugIsMobilePlatformOverride = null);

      expect(
        resolveControlPanelAnchor(
          _state(
            gate: true,
            mode: PhoneLandscapeUseMode.normal,
            sliderType: PhoneLandscapeSliderType.normal,
          ),
          isLandscape: true,
          width: 800,
        ),
        Alignment.bottomCenter,
      );
    });
  });
}

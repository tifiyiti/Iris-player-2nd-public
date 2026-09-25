import 'package:flutter_test/flutter_test.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/pages/player/control_bar/control_bar_layout/control_bar_layout_kind.dart';
import 'package:iris/pages/player/control_bar/control_bar_layout/resolve_control_bar_overflow.dart';
import 'package:iris/pages/player/control_bar/control_bar_widgets/control_bar_constants.dart';

/// Every slot a wide desktop single-line bar can render.
const Set<ControlBarSlot> _desktopSlots = <ControlBarSlot>{
  ControlBarSlot.playPause,
  ControlBarSlot.stop,
  ControlBarSlot.prev,
  ControlBarSlot.next,
  ControlBarSlot.shuffle,
  ControlBarSlot.repeat,
  ControlBarSlot.fit,
  ControlBarSlot.windowFitMode,
  ControlBarSlot.rate,
  ControlBarSlot.volume,
  ControlBarSlot.subtitle,
  ControlBarSlot.backgroundMenu,
  ControlBarSlot.playQueue,
  ControlBarSlot.storage,
  ControlBarSlot.fullscreen,
  ControlBarSlot.more,
};

void main() {
  group('resolveControlBarOverflow', () {
    test('wide bar collapses nothing', () {
      final collapsed = resolveControlBarOverflow(
        availableWidth: 1400,
        present: _desktopSlots,
        volumeWidth: 160,
        sliderReserveWidth: kControlBarSliderMinWidth,
      );
      expect(collapsed, isEmpty);
    });

    test('narrowing pushes the least important slots first', () {
      // 930 is just tight enough to drop storage + shuffle (the two cheapest to
      // lose); nothing further. The single-line bar keeps the seek axis inline,
      // so its reserve is included.
      final collapsed = resolveControlBarOverflow(
        availableWidth: 930,
        present: _desktopSlots,
        volumeWidth: 160,
        sliderReserveWidth: kControlBarSliderMinWidth,
      );
      expect(
        collapsed,
        {ControlBarSlot.storage, ControlBarSlot.shuffle},
      );
    });

    test('an extremely narrow bar collapses every optional slot', () {
      final collapsed = resolveControlBarOverflow(
        availableWidth: 200,
        present: _desktopSlots,
        volumeWidth: 48,
      );
      for (final slot in kControlBarCollapseOrder) {
        expect(collapsed, contains(slot),
            reason: '$slot should collapse when there is no room');
      }
      // Core slots are never part of the policy.
      for (final slot in kControlBarCoreSlots) {
        expect(collapsed, isNot(contains(slot)));
      }
    });

    test('audio strip width is honored (48px icon vs 160px strip)', () {
      // With the strip the bar overflows and collapses slots; the icon width
      // leaves enough room for none.
      final wide = resolveControlBarOverflow(
        availableWidth: 940,
        present: _desktopSlots,
        volumeWidth: 160,
        sliderReserveWidth: kControlBarSliderMinWidth,
      );
      final icon = resolveControlBarOverflow(
        availableWidth: 940,
        present: _desktopSlots,
        volumeWidth: 48,
        sliderReserveWidth: kControlBarSliderMinWidth,
      );
      expect(wide.length, greaterThan(icon.length));
    });
  });

  group('resolveControlBarLayoutKind', () {
    test('width bands map to mobile / tablet / desktop', () {
      expect(
        resolveControlBarLayoutKind(
            width: 500, desktopLayout: DesktopControlBarLayout.singleLine),
        ControlBarLayoutKind.mobile,
      );
      expect(
        resolveControlBarLayoutKind(
            width: 800, desktopLayout: DesktopControlBarLayout.singleLine),
        ControlBarLayoutKind.tablet,
      );
      expect(
        resolveControlBarLayoutKind(
            width: 1200, desktopLayout: DesktopControlBarLayout.singleLine),
        ControlBarLayoutKind.desktopSingle,
      );
      expect(
        resolveControlBarLayoutKind(
            width: 1200, desktopLayout: DesktopControlBarLayout.stacked),
        ControlBarLayoutKind.desktopStacked,
      );
      // Below the tablet breakpoint the stored desktop layout is irrelevant.
      expect(
        resolveControlBarLayoutKind(
            width: 1000, desktopLayout: DesktopControlBarLayout.stacked),
        ControlBarLayoutKind.tablet,
      );
    });
  });

  group('presentControlBarSlots', () {
    test('phone has no rate button, wider layouts do', () {
      final mobile = presentControlBarSlots(
        ControlBarLayoutKind.mobile,
        showFit: true,
        showWindowFit: false,
        hasFullscreen: false,
      );
      expect(mobile, isNot(contains(ControlBarSlot.rate)));

      for (final kind in <ControlBarLayoutKind>[
        ControlBarLayoutKind.tablet,
        ControlBarLayoutKind.desktopSingle,
        ControlBarLayoutKind.desktopStacked,
      ]) {
        expect(
          presentControlBarSlots(kind,
              showFit: true, showWindowFit: true, hasFullscreen: false),
          contains(ControlBarSlot.rate),
        );
      }
    });

    test('window-fit and fullscreen are desktop-only', () {
      final tablet = presentControlBarSlots(
        ControlBarLayoutKind.tablet,
        showFit: true,
        showWindowFit: true,
        hasFullscreen: false,
      );
      expect(tablet, isNot(contains(ControlBarSlot.windowFitMode)));
      expect(tablet, isNot(contains(ControlBarSlot.fullscreen)));

      final desktop = presentControlBarSlots(
        ControlBarLayoutKind.desktopSingle,
        showFit: true,
        showWindowFit: true,
        hasFullscreen: true,
      );
      expect(desktop, contains(ControlBarSlot.windowFitMode));
      expect(desktop, contains(ControlBarSlot.fullscreen));
    });

    test('audio drops fit / window-fit', () {
      final slots = presentControlBarSlots(
        ControlBarLayoutKind.desktopSingle,
        showFit: false,
        showWindowFit: false,
        hasFullscreen: true,
      );
      expect(slots, isNot(contains(ControlBarSlot.fit)));
      expect(slots, isNot(contains(ControlBarSlot.windowFitMode)));
    });
  });

  group('resolveControlBarGroupSupport', () {
    test('phones always support the second group', () {
      expect(
        resolveControlBarGroupSupport(
            isMobile: true,
            desktopPhoneMode: false,
            desktopFloatingEnabled: false),
        isTrue,
      );
    });

    test('desktop needs phone-mode or the desktop floating switch enabled', () {
      expect(
        resolveControlBarGroupSupport(
            isMobile: false,
            desktopPhoneMode: false,
            desktopFloatingEnabled: false),
        isFalse,
      );
      expect(
        resolveControlBarGroupSupport(
            isMobile: false,
            desktopPhoneMode: true,
            desktopFloatingEnabled: false),
        isTrue,
      );
      expect(
        resolveControlBarGroupSupport(
            isMobile: false,
            desktopPhoneMode: false,
            desktopFloatingEnabled: true),
        isTrue,
      );
    });
  });

  group('showStandaloneQuickBarFor', () {
    test('desktop hides the standalone row once the group switch is active', () {
      expect(
        showStandaloneQuickBarFor(isMobile: false, groupSupported: true),
        isFalse,
      );
      expect(
        showStandaloneQuickBarFor(isMobile: false, groupSupported: false),
        isTrue,
      );
    });

    test('phones never show the standalone row', () {
      expect(
        showStandaloneQuickBarFor(isMobile: true, groupSupported: true),
        isFalse,
      );
    });
  });
}

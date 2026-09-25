import 'package:iris/models/store/app_state.dart';
import 'package:iris/pages/player/control_bar/control_bar_layout/resolve_control_bar_overflow.dart';
import 'package:iris/utils/layout_breakpoints.dart';

/// Which LINEAR control-bar arrangement a given available width renders.
///
/// Kept separate from the widget tree so the width→layout decision is
/// unit-testable and shared by `ControlBar` (selection) and the overflow
/// resolver (which slot set is present).
enum ControlBarLayoutKind {
  /// Phone portrait / very narrow: slider + two button rows.
  mobile,

  /// Narrow desktop window / tablet: slider + one button row.
  tablet,

  /// Wide desktop "normal 长条": one line, slider inline between the groups.
  desktopSingle,

  /// Wide desktop PotPlayer-style three-row bar.
  desktopStacked,
}

ControlBarLayoutKind resolveControlBarLayoutKind({
  required double width,
  required DesktopControlBarLayout desktopLayout,
}) {
  if (width < kMobileBreakpoint) return ControlBarLayoutKind.mobile;
  if (width < kTabletBreakpoint) return ControlBarLayoutKind.tablet;
  return desktopLayout == DesktopControlBarLayout.stacked
      ? ControlBarLayoutKind.desktopStacked
      : ControlBarLayoutKind.desktopSingle;
}

/// Whether the bottom control-group switch (playback ↔ 副音) is active for the
/// current context.
///
/// Phones always support the second group. Desktop supports it under the
/// phone-mode opt-in or when its own `floatingButtonDesktop` flag is on (which
/// ships ON) — deliberately NOT tied to the phone's per-orientation flags, so a
/// desktop window that is resized across the square keeps one stable answer.
bool resolveControlBarGroupSupport({
  required bool isMobile,
  required bool desktopPhoneMode,
  required bool desktopFloatingEnabled,
}) =>
    isMobile || desktopPhoneMode || desktopFloatingEnabled;

/// Whether the standalone 副音 quick row still renders on a DESKTOP linear bar.
///
/// In group-switch mode the bar shows exactly ONE group, so the standalone row
/// (governed by `background_playback.quickBarEnabled`) is suppressed — the 副音
/// group owns those controls. Phones never show it. Only the legacy desktop
/// configuration (no phone-mode, floating switch off) keeps the old
/// playback-row + 副音-row arrangement.
bool showStandaloneQuickBarFor({
  required bool isMobile,
  required bool groupSupported,
}) =>
    !isMobile && !groupSupported;

///
/// Slots a given [kind] renders, used to drive the overflow resolver.
///
/// `showFit` / `showWindowFit` carry the per-media conditions from
/// `ControlBarControls` (audio has no fit/window-fit; window-fit is
/// desktop-only). `hasFullscreen` mirrors the desktop-only fullscreen button.
/// The phone layout has no rate button, the wider ones do.
Set<ControlBarSlot> presentControlBarSlots(
  ControlBarLayoutKind kind, {
  required bool showFit,
  required bool showWindowFit,
  required bool hasFullscreen,
}) {
  final Set<ControlBarSlot> slots = <ControlBarSlot>{
    ControlBarSlot.playPause,
    ControlBarSlot.stop,
    ControlBarSlot.prev,
    ControlBarSlot.next,
    ControlBarSlot.shuffle,
    ControlBarSlot.repeat,
    ControlBarSlot.volume,
    ControlBarSlot.subtitle,
    ControlBarSlot.backgroundMenu,
    ControlBarSlot.playQueue,
    ControlBarSlot.storage,
    ControlBarSlot.more,
  };
  if (showFit) slots.add(ControlBarSlot.fit);
  if (hasFullscreen) slots.add(ControlBarSlot.fullscreen);
  switch (kind) {
    case ControlBarLayoutKind.mobile:
      break;
    case ControlBarLayoutKind.tablet:
    case ControlBarLayoutKind.desktopSingle:
    case ControlBarLayoutKind.desktopStacked:
      slots.add(ControlBarSlot.rate);
  }
  if (showWindowFit &&
      (kind == ControlBarLayoutKind.desktopSingle ||
          kind == ControlBarLayoutKind.desktopStacked)) {
    slots.add(ControlBarSlot.windowFitMode);
  }
  return slots;
}

import 'package:flutter/material.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/utils/layout_breakpoints.dart';
import 'package:iris/utils/platform.dart' show isDesktop, isMobilePlatform, isWindows;

extension PhoneLandscapeSliderTypeHelper on PhoneLandscapeSliderType {
  /// Whether this mode uses the circular slider
  bool get isCircle => this == PhoneLandscapeSliderType.circleLeft || this == PhoneLandscapeSliderType.circleRight;

  /// Whether the circular slider is placed on the left side
  bool get isLeft => this == PhoneLandscapeSliderType.circleLeft;

  /// Alignment for the control panel
  Alignment get alignmentBottom {
    switch (this) {
      case PhoneLandscapeSliderType.circleLeft:
        return Alignment.bottomLeft;
      case PhoneLandscapeSliderType.circleRight:
        return Alignment.bottomRight;
      case PhoneLandscapeSliderType.normal:
        return Alignment.bottomCenter;
    }
  }

  /// Alignment for the control panel
  Alignment get alignmentTop {
    switch (this) {
      case PhoneLandscapeSliderType.circleLeft:
        return Alignment.topLeft;
      case PhoneLandscapeSliderType.circleRight:
        return Alignment.topRight;
      case PhoneLandscapeSliderType.normal:
        return Alignment.topCenter;
    }
  }
}

extension PhoneLandscapeUseModeHelper on PhoneLandscapeUseMode {
  bool get usesOneHandedControls => this != PhoneLandscapeUseMode.normal;

  bool get isLeftHanded => this == PhoneLandscapeUseMode.leftSide || this == PhoneLandscapeUseMode.leftHanded;
  bool get isLeftSide => this == PhoneLandscapeUseMode.leftSide || this == PhoneLandscapeUseMode.leftHanded;
  bool get isRightSide => this == PhoneLandscapeUseMode.rightSide || this == PhoneLandscapeUseMode.rightHanded;

  Alignment get controlBarAlignment {
    switch (this) {
      case PhoneLandscapeUseMode.normal:
        return Alignment.bottomCenter;
      case PhoneLandscapeUseMode.rightSide:
      case PhoneLandscapeUseMode.rightHanded:
        return Alignment.bottomRight;
      case PhoneLandscapeUseMode.leftSide:
      case PhoneLandscapeUseMode.leftHanded:
        return Alignment.bottomLeft;
    }
  }
}

/// Meta-settings presentation of the slider type. The one-handed right/left
/// modes auto-select the matching classic circle placement (the old
/// circleRight/circleLeft options are folded away).
enum MetaSliderTypeOption { normal, rightSide, leftSide }

MetaSliderTypeOption metaSliderTypeOption(PhoneLandscapeUseMode mode) {
  switch (mode) {
    case PhoneLandscapeUseMode.rightSide:
    case PhoneLandscapeUseMode.rightHanded:
      return MetaSliderTypeOption.rightSide;
    case PhoneLandscapeUseMode.leftSide:
    case PhoneLandscapeUseMode.leftHanded:
      return MetaSliderTypeOption.leftSide;
    case PhoneLandscapeUseMode.normal:
      return MetaSliderTypeOption.normal;
  }
}

String metaSliderTypeLabel(MetaSliderTypeOption option, AppLocalizations t) =>
    switch (option) {
      MetaSliderTypeOption.normal => t.phone_slider_normal,
      MetaSliderTypeOption.rightSide => t.phone_slider_right,
      MetaSliderTypeOption.leftSide => t.phone_slider_left,
    };

/// Whether the sideway total panel requires a tap/click to appear (hover
/// still shows title/cursor via normal `showControl`). Requires the gate +
/// `slider.requireClick` (default OFF).
///
/// Desktop has its own hover policy: the `app.desktopHoverShowControlBar`
/// snapshot bit (also gate-gated) keeps a mouse move from revealing the bar —
/// it appears on click instead. Both rules funnel through this one function so
/// every hover/tap/panel-visibility path stays consistent.
bool shouldRequireClickToShowPanel(AppState state) =>
    shouldRequireClickToShowPanelFrom(
      useMetadataSettings: state.useMetadataSettings,
      desktopHoverShowControlBar: state.desktopHoverShowControlBar,
      sidewayPanelRequireClick: state.sidewayPanelRequireClick,
      oneHandedControls: state.phoneLandscapeUseMode.usesOneHandedControls,
    );

/// [shouldRequireClickToShowPanel] over already-selected fields.
///
/// Lets a widget subscribe to a narrow AppState slice (record selector) instead
/// of the whole object, so it does not rebuild on unrelated app-state changes.
/// The AppState overload delegates here — this stays the single authority.
bool shouldRequireClickToShowPanelFrom({
  required bool useMetadataSettings,
  required bool desktopHoverShowControlBar,
  required bool sidewayPanelRequireClick,
  required bool oneHandedControls,
}) {
  if (!useMetadataSettings) return false;
  if (isDesktop) return !desktopHoverShowControlBar;
  if (!sidewayPanelRequireClick) return false;
  if (!oneHandedControls) return false;
  return true;
}

/// Whether a PASSIVE desktop hover reveals the title bar. The control-bar
/// toggle implies the title (a full bar always carries its title); with both
/// switches OFF a hover reveals only the cursor. Non-desktop and gate-OFF keep
/// today's hover-reveals-everything behavior so legacy installs are untouched.
/// Explicit shows never consult this — only `isHoverReveal` states do.
bool desktopHoverRevealsTitle(AppState state) {
  if (!state.useMetadataSettings || !isDesktop) return true;
  return state.desktopHoverShowTitle || state.desktopHoverShowControlBar;
}

/// Screen anchor of the sideway one-handed panel.
///
/// Meta gate ON:
/// - phone (`isMobilePlatform`) → `slider.phonePosH` left/right only, posV fixed
///   bottom; desktop `slider.posH/posV` rows are ignored so the two never
///   overwrite each other.
/// - desktop → 9-grid `slider.posH/posV` rows.
/// Gate OFF → legacy mode-derived corner (bottom-left/right), so a stale
/// stored anchor can never leak into legacy runs. Non-side modes always
/// anchor bottom-center.
Alignment resolveSidePanelAlignment(AppState state) {
  if (!state.phoneLandscapeUseMode.usesOneHandedControls) {
    return Alignment.bottomCenter;
  }
  if (!state.useMetadataSettings) {
    return state.phoneLandscapeUseMode.controlBarAlignment;
  }
  if (isMobilePlatformForSidePanel()) {
    final double dx = switch (state.mobileSidePositionH) {
      PhoneSidePositionH.left => -1.0,
      PhoneSidePositionH.center => 0.0,
      PhoneSidePositionH.right => 1.0,
    };
    return Alignment(dx, 1.0);
  }
  final double dx = switch (state.phoneSidePositionH) {
    PhoneSidePositionH.left => -1.0,
    PhoneSidePositionH.center => 0.0,
    PhoneSidePositionH.right => 1.0,
  };
  final double dy = switch (state.phoneSidePositionV) {
    PhoneSidePositionV.top => -1.0,
    PhoneSidePositionV.middle => 0.0,
    PhoneSidePositionV.bottom => 1.0,
  };
  return Alignment(dx, dy);
}

/// Screen anchor of the control panel box as it is ACTUALLY placed.
///
/// [resolveSidePanelAlignment] answers "where does the one-handed panel want to
/// sit"; this answers "where does the panel end up on screen", which is what the
/// overlay aligns the panel box with AND what that box uses to decide which way
/// its bottom button rows face. Single authority, so the panel and its rows can
/// never disagree about which side is which.
///
/// Precedence mirrors the historical inline chain: the one-handed panel
/// (Windows desk or phone landscape) docks by the 9-grid anchor; the plain
/// circle-left/right slider docks by its own corner inside the mobile/tablet
/// width band; anything else stays bottom-centre.
Alignment resolveControlPanelAnchor(
  AppState state, {
  required bool isLandscape,
  required double width,
}) {
  if (state.phoneLandscapeUseMode.usesOneHandedControls &&
      (isWindows || (isMobilePlatform && isLandscape))) {
    return resolveSidePanelAlignment(state);
  }
  if (isMobilePlatform &&
      state.phoneLandscapeSliderType.isCircle &&
      width >= kMobileBreakpoint &&
      width < kTabletBreakpoint) {
    return state.phoneLandscapeSliderType.alignmentBottom;
  }
  return Alignment.bottomCenter;
}

/// Whether the control panel is visible.
///
/// Single authority: [ControlsOverlay] gates the bar (and its input, semantics
/// and tickers) with this, and the floating bottom-group switch button gates
/// itself with it too, so the two can never disagree about whether the bar is
/// up — the switch rides the panel's visibility instead of floating alone over
/// a hidden control bar.
///
/// The panel is FORCED up while the 副音 align editor owns it, while a non-video
/// file plays (audio pins the bar) or during a scrub session; otherwise it
/// follows [isShowControl] and the reveal policy.
bool resolveControlPanelVisible({
  required AppState appState,
  required bool isShowControl,
  required bool isHoverReveal,
  required bool isPanelClickArmed,
  required bool editing,
  required bool isVideo,
  required bool dragActive,
}) =>
    resolveControlPanelVisibleFrom(
      requireClick: shouldRequireClickToShowPanel(appState),
      isShowControl: isShowControl,
      isHoverReveal: isHoverReveal,
      isPanelClickArmed: isPanelClickArmed,
      editing: editing,
      isVideo: isVideo,
      dragActive: dragActive,
    );

/// [resolveControlPanelVisible] over an already-resolved [requireClick].
///
/// Same contract; the AppState overload delegates here so a caller that only
/// needs the click-to-show bit can avoid subscribing to the whole AppState.
bool resolveControlPanelVisibleFrom({
  required bool requireClick,
  required bool isShowControl,
  required bool isHoverReveal,
  required bool isPanelClickArmed,
  required bool editing,
  required bool isVideo,
  required bool dragActive,
}) {
  if (editing || !isVideo || dragActive) return true;
  // Desktop explicit shows (incl. startup) always reveal the bar; a passive
  // hover obeys the `app.desktopHoverShow*` switches. Mobile keeps the original
  // click-latch rule (`requireClick` is the one-handed side-panel gate there).
  final bool panelRevealed = isDesktop
      ? (!isHoverReveal || !requireClick || isPanelClickArmed)
      : (!requireClick || isPanelClickArmed);
  return isShowControl && panelRevealed;
}

bool isMobilePlatformForSidePanel() {
  try {
    return isMobilePlatform;
  } catch (_) {
    return false;
  }
}

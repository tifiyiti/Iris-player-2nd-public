import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'package:iris/utils/platform.dart';

/// AXTree stability helper for Windows UIA bridge (flutter/flutter #182444).
///
/// Wraps a control-bar button in a semantics boundary and makes its hover
/// tooltip a11y-aware: when a UIA client / screen reader is attached the
/// tooltip only appears on tap, so its OverlayPortal is never mounted during
/// playback and cannot trigger the traversal-graft dangling-node race that corrupts
/// `ui::AXTree`.
///
/// Gating condition: `semanticsEnabled || accessibleNavigation`.
/// Windows UIA clients (NVDA et al.) activate semantics WITHOUT necessarily
/// setting `accessibleNavigation`, so keying on `MediaQuery
/// .accessibleNavigation` alone never engages tap-only mode under NVDA and
/// hover tooltips keep grafting into the root overlay mid-playback.

/// Reactive gate: TRUE when any assistive client may be listening.
final ValueNotifier<bool> kA11yTooltipGate = ValueNotifier<bool>(false);

/// Tooltip payload for row-level popups/buttons inside scrolling lists.
///
/// WHY (flutter/flutter #182444): a hover Tooltip grafts its OverlayPortal
/// into the ROOT overlay while the mouse passes over rows inside a
/// two-pane semantics viewport (ListView / ScrollablePositionedList) — a
/// documented Windows AXTree-corruption trigger. On Windows the payload is
/// dropped entirely (empty string → Tooltip returns the child unwrapped:
/// no overlay, no semantics); every other platform keeps the label, since
/// Android TalkBack has no graft bug and must keep announcing the action.
///
/// `null` [message] means "keep the widget's default label" on
/// non-Windows platforms (e.g. PopupMenuButton's localized "Show menu").
String? rowTooltip(String? message) => isWindows ? '' : message;

bool _gateHooked = false;

void _ensureGateHooked() {
  if (_gateHooked) return;
  _gateHooked = true;
  void update() {
    kA11yTooltipGate.value = SemanticsBinding.instance.semanticsEnabled ||
        WidgetsBinding
            .instance.platformDispatcher.accessibilityFeatures.accessibleNavigation;
  }

  // Official reactive API — no platform-dispatcher callback clobbering.
  SemanticsBinding.instance.addSemanticsEnabledListener(update);
  final prev = WidgetsBinding
      .instance.platformDispatcher.onAccessibilityFeaturesChanged;
  WidgetsBinding.instance.platformDispatcher.onAccessibilityFeaturesChanged =
      () {
    prev?.call();
    update();
  };
  update();
}

Widget a11yTooltip({
  required BuildContext context,
  required String message,
  required Widget child,
  bool longPressPassthrough = false,
}) {
  _ensureGateHooked();
  return ValueListenableBuilder<bool>(
    valueListenable: kA11yTooltipGate,
    builder: (context, a11yActive, _) => Semantics(
      container: true,
      child: Tooltip(
        message: message,
        // `longPressPassthrough` keeps the a11y label but stops the Tooltip
        // from claiming the long-press gesture, so a child long-press (e.g.
        // the frame-step fast-repeat) always wins on touch platforms.
        triggerMode: a11yActive
            ? TooltipTriggerMode.tap
            : (longPressPassthrough ? TooltipTriggerMode.manual : null),
        child: child,
      ),
    ),
  );
}

/// Variant for [IconButton] that keeps the call-site concise.
Widget a11yTooltipIconButton({
  required BuildContext context,
  required String tooltip,
  required Widget icon,
  required VoidCallback? onPressed,
  ButtonStyle? style,
  VisualDensity? visualDensity,
}) {
  _ensureGateHooked();
  return ValueListenableBuilder<bool>(
    valueListenable: kA11yTooltipGate,
    builder: (context, a11yActive, _) => Semantics(
      container: true,
      child: Tooltip(
        message: tooltip,
        triggerMode: a11yActive ? TooltipTriggerMode.tap : null,
        child: IconButton(
          icon: icon,
          onPressed: onPressed,
          style: style,
          visualDensity: visualDensity,
        ),
      ),
    ),
  );
}

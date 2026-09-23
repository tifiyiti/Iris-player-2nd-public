// ignore: unnecessary_library_name
library my_app.globals;

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

List<String> arguments = [];
String? initUri;

/// Desktop-entry launch latch (app_identity feature): set during startup
/// from the Android shortcut intent; consumed exactly once by the launch
/// router in Home.
String? entryLaunchId;
PermissionStatus? storagePermissionStatus;

/// Live key of the MORE / rate popup-menu buttons, published by the button that
/// is actually mounted (see [usePublishedGlobalKey] for why these are per-mount
/// rather than shared). The keyboard shortcuts open whichever button is live.
final ValueNotifier<GlobalKey<PopupMenuButtonState>?> moreMenuKeyNotifier =
    ValueNotifier<GlobalKey<PopupMenuButtonState>?>(null);
final ValueNotifier<GlobalKey<PopupMenuButtonState>?> rateMenuKeyNotifier =
    ValueNotifier<GlobalKey<PopupMenuButtonState>?>(null);

/// Live key of the one-handed side PANEL box, published by
/// `CircleSliderLayout` while the panel is mounted (null otherwise).
///
/// Readers take a fresh lookup at use time (`value?.currentContext`) exactly
/// like a shared key would: `showRingDialStyleControlPopover` /
/// `showCircleStyleControlPopover` anchor their cards to the panel's
/// centre-facing edge.
///
/// WHY a published PER-MOUNT key instead of one shared [GlobalKey]
/// (flutter/flutter #177693 / #188500, the #182444 family): a shared key lets a
/// NEW panel element re-take the OLD, deactivated one
/// (`Element._retakeInactiveElement`, framework.dart:4481 — it even steals a
/// still-active child). Re-activating it re-activates every `OverlayPortal`
/// inside (the buttons' Tooltips, a Slider's value indicator), and
/// `_OverlayPortalElement.activate` grafts the deferred child into the root
/// overlay BEFORE the new parent is attached, so the mutation lands with no
/// actively-laying-out ancestor: `_RenderLayoutBuilder was mutated in
/// performLayout`, then a poisoned element tree
/// (`Lost connection to device`, bogus `RenderFlex overflowed by 97890
/// pixels`). A per-mount key object can never be re-taken, so the panel always
/// mounts fresh and nothing is ever re-activated.
final ValueNotifier<GlobalKey?> sidePanelKeyNotifier =
    ValueNotifier<GlobalKey?>(null);

/// The APB align editor's own side-panel box.
///
/// The editor and the normal one-handed panel are mutually exclusive subtrees
/// rendered by `ControlsOverlay`; a per-mount key keeps the editor subtree
/// purely mount/unmount — never an activation (see [usePublishedGlobalKey]).
final ValueNotifier<GlobalKey?> apbEditorPanelKeyNotifier =
    ValueNotifier<GlobalKey?>(null);

/// Live key of the shared CONTROL BAR panel box (the one-handed side total
/// panel, or the linear bottom bar), published by `ControlsOverlay` while it is
/// mounted (null otherwise).
///
/// The picture-fullscreen playlist dock reads it to EXCLUDE the bar from its
/// right-edge summon strip: the side panel is anchored against that same edge,
/// so hovering its slider used to summon the queue over the very control the
/// user was operating. Because the bar is translated off-screen while hidden,
/// the published box reports an off-screen rect at that point and the exclusion
/// self-disables.
final ValueNotifier<GlobalKey?> controlPanelKeyNotifier =
    ValueNotifier<GlobalKey?>(null);

const double speedSelectorItemWidth = 64.0;
const List<double> speedStops = [
  0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, //
  1.0, 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8, 1.9,
  2.0, 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8, 2.9,
  3.0, 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 3.8, 3.9,
  4.0, 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 4.7, 4.8, 4.9,
  5.0, 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 5.7, 5.8, 5.9,
  6.0, 6.1, 6.2, 6.3, 6.4, 6.5, 6.6, 6.7, 6.8, 6.9,
  7.0, 7.1, 7.2, 7.3, 7.4, 7.5, 7.6, 7.7, 7.8, 7.9,
  8.0, 8.1, 8.2, 8.3, 8.4, 8.5, 8.6, 8.7, 8.8, 8.9,
  9.0, 9.1, 9.2, 9.3, 9.4, 9.5, 9.6, 9.7, 9.8, 9.9,
  10.0,
];

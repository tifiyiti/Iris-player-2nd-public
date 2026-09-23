import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/models/store/gesture/gesture_layouts_default.dart';
import 'package:iris/models/store/gesture/gesture_layouts_left.dart';
import 'package:iris/models/store/gesture/gesture_layouts_right.dart';
import 'package:iris/models/store/gesture_region.dart';

/*
Gestures
├─ Portrait
│   └─ Gesture style
│       ○ Classic
│       ○ Region-based
│
└─ Landscape
└─ Gesture style
│       Classic
│       Region-based
│       Right-hand
│       Left-hand
*/

enum GestureOrientation {
  portrait,
  landscape,
}

GestureOrientation resolveGestureOrientation({
  required AppState state,
  required Orientation realOrientation,
}) {
  // Desktop → always portrait gestures
  if (!(Platform.isAndroid || Platform.isIOS)) {
    return GestureOrientation.portrait;
  }

  // Phone → respect runtime orientation override
  switch (state.runtimeOrientation) {
    case ScreenOrientation.landscape:
      return GestureOrientation.landscape;
    case ScreenOrientation.portrait:
      return GestureOrientation.portrait;
    case ScreenOrientation.device:
      return realOrientation == Orientation.landscape ? GestureOrientation.landscape : GestureOrientation.portrait;
  }
}

GestureLayout layout(
  GestureIntent intent,
  List<GestureRegion> regions,
) =>
    GestureLayout(
      intent: intent,
      regions: regions,
    );

/// Fills an empty stored vertical long-press layout with the default one.
/// Old blobs persisted `longPressPanVertical` as empty (it used to be
/// unbound), so merging them over the defaults would keep swallowing
/// vertical pans. Non-empty stored layouts are user edits and survive.
Map<GestureIntent, GestureLayout> migrateEmptyLongPressPanVertical(
  Map<GestureIntent, GestureLayout> stored,
  Map<GestureIntent, GestureLayout> defaults,
) {
  final current = stored[GestureIntent.longPressPanVertical];
  if (current != null && current.regions.isNotEmpty) return stored;
  final fallback = defaults[GestureIntent.longPressPanVertical];
  if (fallback == null || fallback.regions.isEmpty) return stored;
  return {...stored, GestureIntent.longPressPanVertical: fallback};
}

final defaultGestureLayoutProfiles = {
  kLayoutRegionPortrait: defaultGestureLayouts,
  kLayoutRegion: defaultGestureLayouts,
  kLayoutRegionRightSide: rightSideGestureLayouts,
  kLayoutRegionLeftSide: leftSideGestureLayouts,
};

GestureMode resolveGestureMode({
  required AppState state,
  required Orientation orientation,
  required bool isPhone,
}) {
  if (!isPhone) {
    return GestureMode.classic;
  }
  // Legacy mode: no region gestures
  if (!state.useMetadataSettings) {
    return GestureMode.classic;
  }

  if (orientation == Orientation.landscape) {
    switch (state.landscapeGestureProfile) {
      case LandscapeGestureProfile.classic:
        return GestureMode.classic;
      case LandscapeGestureProfile.region:
        return GestureMode.region;
      case LandscapeGestureProfile.rightSide:
      case LandscapeGestureProfile.rightHand:
        return GestureMode.rightSideLandscape;
      case LandscapeGestureProfile.leftSide:
      case LandscapeGestureProfile.leftHand:
        return GestureMode.leftSideLandscape;
      case LandscapeGestureProfile.tagPlay:
        return GestureMode.region;
    }
  }

  // portrait: legacy handled above, meta always region (normal)
  switch (state.portraitGestureProfile) {
    case PortraitGestureProfile.classic:
      return GestureMode.classic;
    case PortraitGestureProfile.region:
    case PortraitGestureProfile.tagPlay:
      return GestureMode.region;
  }
}

// Map<GestureIntent, GestureLayout> resolveActiveLayouts(
//   AppState state,
//   Orientation realOrientation,
// ) {
//   final gestureOrientation = resolveGestureOrientation(
//     state: state,
//     realOrientation: realOrientation,
//   );
//
//   final key = switch (gestureOrientation) {
//     GestureOrientation.landscape => switch (state.landscapeGestureProfile) {
//         LandscapeGestureProfile.region => kLayoutDefault,
//         LandscapeGestureProfile.rightHand => kLayoutRightHand,
//         LandscapeGestureProfile.leftHand => kLayoutLeftHand,
//         _ => kLayoutDefault,
//       },
//     GestureOrientation.portrait => switch (state.portraitGestureProfile) {
//         PortraitGestureProfile.region => kLayoutDefault,
//         PortraitGestureProfile.classic => kLayoutDefault,
//       },
//   };
//
//   return state.gestureLayoutProfiles[key] ?? defaultGestureLayoutProfiles[key]!;
// }

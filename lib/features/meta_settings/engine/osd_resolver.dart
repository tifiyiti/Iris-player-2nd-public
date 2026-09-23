import 'package:flutter/widgets.dart' show Alignment;
import 'package:iris/models/store/app_state.dart';

// Pure resolver for the PotPlayer-style keyboard OSD.
// Follows the same contract as `resolveBrowseMediaScope`:
// when the metadata gate is OFF, the OSD degrades to hidden.

bool resolveOsdEnabled(AppState state, bool metadataEnabled) =>
    metadataEnabled ? state.osdEnabled : false;

bool resolveOsdShouldShow(
  AppState state,
  bool metadataEnabled, {
  required bool isShowControl,
}) {
  if (!resolveOsdEnabled(state, metadataEnabled)) return false;
  if (state.osdVisibilityMode == OsdVisibilityMode.hideWhenControlVisible &&
      isShowControl) {
    return false;
  }
  return true;
}

Alignment resolveOsdAlignment(OsdHAlign h, OsdVAlign v) {
  final double x = switch (h) {
    OsdHAlign.left => -1.0,
    OsdHAlign.center => 0.0,
    OsdHAlign.right => 1.0,
  };
  final double y = switch (v) {
    OsdVAlign.top => -1.0,
    OsdVAlign.middle => 0.0,
    OsdVAlign.bottom => 1.0,
  };
  return Alignment(x, y);
}

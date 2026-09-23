import 'package:iris/models/store/gesture/gesture_actions.dart';
import 'package:iris/models/store/gesture/gesture_region_layout.dart';
import 'package:iris/models/store/gesture/gesture_rects.dart.dart';
import 'package:iris/models/store/gesture_region.dart';

/// Legacy right-hand (full-height six-cell) — kept for reference.
@Deprecated('Use rightSideGestureLayouts')
final Map<GestureIntent, GestureLayout> rightHandGestureLayouts = rightSideGestureLayouts;

/// Meta right-side: top 15% tag strip + below 2-column six-cell (0.15-1.00).
/// Tap is a full-height 2x3 six-grid (rows 25% / 30% / 45%): upper-right two
/// cells are `none` (dead zone under the holding thumb), the other four
/// `toggleControls`. DoubleTap keeps the legacy seek/step/pause mapping verbatim.
final Map<GestureIntent, GestureLayout> rightSideGestureLayouts = {
  GestureIntent.tap: layout(
    GestureIntent.tap,
    [
      r(kRightTop25, none),
      r(kRightMid30, none),
      r(kRightBot45, toggle),
      r(kLeftTop25, toggle),
      r(kLeftMid30, toggle),
      r(kLeftBottom45, toggle),
    ],
  ),
  GestureIntent.doubleTap: layout(
    GestureIntent.doubleTap,
    [
      r(kTagTop15Left, openTags),
      r(kTagTop15Right, openTags),
      r(kLeftTop35Below, playPause),
      r(kLeftMid35Below, playPause),
      r(kLeftBottom30Below, playPause),
      r(kRightTop35Below, seekF),
      r(kRightMid35Below, seekB),
      r(kRightBot30Below, playPause),
    ],
  ),
  GestureIntent.panHorizontal: layout(
    GestureIntent.panHorizontal,
    [
      r(kFullScreen, seekTo),
    ],
  ),
  GestureIntent.panVertical: layout(
    GestureIntent.panVertical,
    [
      r(kRS_40_0_40, none),
      r(kRS_40_40_20, bright),
      r(kRS_60_20_20, adjustSeekStep),
      r(kRS_80_20_20, volume),
    ],
  ),
  GestureIntent.longPress: layout(
    GestureIntent.longPress,
    [
      r(kVTop35, speedActivate),
      r(kVMid35, speedActivate),
      r(kVBot30, showRate),
    ],
  ),
  GestureIntent.longPressPanHorizontal: layout(
    GestureIntent.longPressPanHorizontal,
    [
      r(kVTop35, speedUpdate),
      r(kVMid35, speedUpdate),
      r(kVBot30, updateRate),
    ],
  ),
  GestureIntent.longPressPanVertical: layout(
    GestureIntent.longPressPanVertical,
    [
      r(kVTop35, speedUpdate),
      r(kVMid35, speedUpdate),
      r(kVBot30, updateRate),
    ],
  ),
};

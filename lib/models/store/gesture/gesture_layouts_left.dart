import 'package:iris/models/store/gesture/gesture_actions.dart';
import 'package:iris/models/store/gesture/gesture_region_layout.dart';
import 'package:iris/models/store/gesture/gesture_rects.dart.dart';
import 'package:iris/models/store/gesture_region.dart';

/// Legacy left-hand — kept for reference.
@Deprecated('Use leftSideGestureLayouts')
final Map<GestureIntent, GestureLayout> leftHandGestureLayouts = leftSideGestureLayouts;

/// Meta left-side: top 15% tag strip + below 2-column six-cell (0.15-1.00).
/// Tap is a full-height 2x3 six-grid (rows 25% / 30% / 45%): upper-left two
/// cells are `none` (dead zone under the holding thumb), the other four
/// `toggleControls`. DoubleTap keeps the legacy seek/step/pause mapping verbatim.
final Map<GestureIntent, GestureLayout> leftSideGestureLayouts = {
  GestureIntent.tap: layout(
    GestureIntent.tap,
    [
      r(kLeftTop25, none),
      r(kLeftMid30, none),
      r(kLeftBottom45, toggle),
      r(kRightTop25, toggle),
      r(kRightMid30, toggle),
      r(kRightBot45, toggle),
    ],
  ),
  GestureIntent.doubleTap: layout(
    GestureIntent.doubleTap,
    [
      r(kTagTop15Left, openTags),
      r(kTagTop15Right, openTags),
      r(kLeftTop35Below, seekF),
      r(kLeftMid35Below, seekB),
      r(kLeftBottom30Below, playPause),
      r(kRightTop35Below, playPause),
      r(kRightMid35Below, playPause),
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
      r(kLS_0_20_20, bright),
      r(kLS_20_20_20, adjustSeekStep),
      r(kLS_40_20_20, volume),
      r(kLS_60_40_40, none),
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

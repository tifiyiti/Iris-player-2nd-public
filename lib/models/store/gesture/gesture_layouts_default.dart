import 'package:iris/models/store/gesture/gesture_actions.dart';
import 'package:iris/models/store/gesture/gesture_region_layout.dart';
import 'package:iris/models/store/gesture/gesture_rects.dart.dart';
import 'package:iris/models/store/gesture_region.dart';

/// Legacy reference (full-height 25/50/25) — kept for reference, not used in meta.
@Deprecated('Use meta partitioned layout')
final Map<GestureIntent, GestureLayout> legacyDefaultGestureLayouts = {
  GestureIntent.tap: layout(
    GestureIntent.tap,
    [
      r(kFullScreen, toggle),
    ],
  ),
  GestureIntent.doubleTap: layout(
    GestureIntent.doubleTap,
    [
      r(kLeftQuarter, seekB),
      r(kMiddleHalf, playPause),
      r(kRightQuarter, seekF),
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
      r(kLeft30, bright),
      r(kMid40, adjustSeekStep),
      r(kRight30, volume),
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
  GestureIntent.hover: layout(
    GestureIntent.hover,
    [
      r(kFullScreen, toggle),
    ],
  ),
};

/// Meta unified layout: physically partitioned, STRICT n×m grid (no
/// straddling rects). Default doubleTap is the 3×3 spec: 2 vertical lines
/// (0.25/0.75) × 2 horizontal lines (0.15/0.70) → 9 cells — top row all tag,
/// middle row seekB|playPause|seekF, bottom row seekB|tag|seekF.
final Map<GestureIntent, GestureLayout> defaultGestureLayouts = {
  GestureIntent.tap: layout(
    GestureIntent.tap,
    [
      r(kFullScreen, toggle),
    ],
  ),
  GestureIntent.doubleTap: layout(
    GestureIntent.doubleTap,
    [
      r(kGridTagTopLeft, seekB),
      r(kGridTagTopCenter, playPause),
      r(kGridTagTopRight, seekF),
      r(kGridMidLeft, seekB),
      r(kGridMidCenter, playPause),
      r(kGridMidRight, seekF),
      r(kGridBotLeft, seekB),
      r(kGridBotCenter, openTags),
      r(kGridBotRight, seekF),
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
      r(kLeft30, bright),
      r(kMid40, adjustSeekStep),
      r(kRight30, volume),
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
  GestureIntent.hover: layout(
    GestureIntent.hover,
    [
      r(kFullScreen, toggle),
    ],
  ),
};

/// Deprecated tagPlay alias — meta now unified.
@Deprecated('Use defaultGestureLayouts with kTagTop15')
final Map<GestureIntent, GestureLayout> tagPlayGestureLayouts = defaultGestureLayouts;
